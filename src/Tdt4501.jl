module Tdt4501

export test

using Allocations
using Gurobi
using Graphs
using JuMP
import Logging
using Matroids

const GRB_ENV_REF = Ref{Gurobi.Env}()
const epsilon = 1e-5
const check_allocation = check_partition

function __init__()
    global GRB_ENV_REF
    GRB_ENV_REF[] = Gurobi.Env()

    debug_logger = Logging.ConsoleLogger(Logging.Debug)
    Logging.global_logger(debug_logger)

    return
end

function test()
    optimizer = optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV_REF[]), "LogToConsole" => 0)

    G = SimpleGraph(7, 0)
    add_edge!(G, 1, 2)
    add_edge!(G, 2, 3)
    add_edge!(G, 3, 4)
    add_edge!(G, 4, 1)

    add_edge!(G, 5, 6)
    add_edge!(G, 6, 7)
    add_edge!(G, 7, 5)

    matroid = GraphicMatroid(G)
    @debug "Is independent? $(is_indep(matroid, [1, 2, 3, 4]))"
    @debug "Is independent? $(is_indep(matroid, [5, 6, 7]))"
    @debug "Matroid rank: $(rank(matroid))"

    V = Profile([2 2 2 2 1 1 1; 1 1 1 1 2 2 2])

    loop_ctx = Allocations.init_mip(V, optimizer) |>
               Allocations.achieve_mnw(false)
    loop_ctx = matroid_constraint_loop(loop_ctx, matroid)

    res = Allocations.mnw_result(loop_ctx)
    @info "Result for loop method: $(res.alloc), mnw = $(res.mnw)"

    lazy_ctx = Allocations.init_mip(V, optimizer) |>
               Allocations.achieve_mnw(false)
    lazy_ctx = matroid_constraint_lazy(lazy_ctx, matroid)

    res = Allocations.mnw_result(lazy_ctx)
    @info "Result for lazy method: $(res.alloc), mnw = $(res.mnw)"
end

function matroid_constraint_loop(ctx::Allocations.MIPContext, matroid::Matroid)
    constraints = Pair[]
    feasible = false

    while !feasible
        ctx = Allocations.solve_mip(ctx)

        feasible = true
        for B in ctx.alloc.bundle
            if !is_indep(matroid, B)
                feasible = false
                bundle_rank = rank(matroid, B)
                @debug "Adding cardinality constraint for dependent set: $B => $bundle_rank"
                push!(constraints, B => bundle_rank)
            end
        end

        if !feasible
            set_start_values(ctx.model)
            ctx = ctx |> Allocations.enforce(Counts(constraints...))
        end
    end

    return ctx
end

function matroid_constraint_lazy(ctx::Allocations.MIPContext, matroid::Matroid)
    set_attribute(ctx.model, MOI.LazyConstraintCallback(), c -> _matroid_constraint_callback(c, ctx, matroid))
    Allocations.solve_mip(ctx)
end

function _matroid_constraint_callback(cb_data, ctx, matroid::Matroid)
    if callback_node_status(cb_data, ctx.model) != MOI.CALLBACK_NODE_STATUS_INTEGER
        return
    end

    V = ctx.profile
    alloc = Allocation(na(V), ni(V))

    for i in agents(V), g in items(V)
        val = callback_value(cb_data, ctx.alloc_var[i, g])
        @assert val ≤ epsilon || val ≥ 1 - epsilon
        val ≥ 1.0 - epsilon && give!(alloc, i, g)
    end

    isnothing(check_allocation) || check_allocation(alloc)

    for B in alloc.bundle
        if !is_indep(matroid, B)
            bundle_rank = rank(matroid, B)
            @debug "Adding cardinality constraint for dependent set: $B => $bundle_rank"
            for i in agents(V)
                con = @build_constraint(sum(ctx.alloc_var[i, g] for g in B) <= bundle_rank)
                MOI.submit(ctx.model, MOI.LazyConstraint(cb_data), con)
            end
        end
    end
end

end # module
