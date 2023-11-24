module Tdt4501

export bench

using Allocations
using BenchmarkTools
import GLPK
using Graphs
import Gurobi
using JuMP
import Logging
using Matroids
import Random

const GRB_ENV_REF = Ref{Gurobi.Env}()
const epsilon = 1e-5
const check_allocation = check_partition

function __init__()
    global GRB_ENV_REF
    GRB_ENV_REF[] = Gurobi.Env()

    debug_logger = Logging.ConsoleLogger(Logging.Info)
    Logging.global_logger(debug_logger)

    return
end

function bench()
    time_limit = 300
    gurobi = optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV_REF[]), "LogToConsole" => 0, "TimeLimit" => time_limit)
    glpk = optimizer_with_attributes(GLPK.Optimizer, "tm_lim" => time_limit * 1_000)
    seed = 42424242

    # Warmup
    @info "Warming up..."
    p1 = rand_problem_stream(gurobi, Random.Xoshiro(seed))()
    matroid_constraint_loop(p1.ctx, p1.M)
    matroid_constraint_lazy(p1.ctx, p1.M)
    p2 = rand_problem_stream(glpk, Random.Xoshiro(seed))()
    matroid_constraint_loop(p2.ctx, p2.M)
    matroid_constraint_lazy(p2.ctx, p2.M)
    @info "Warmup finished"

    BenchmarkTools.DEFAULT_PARAMETERS.samples = 10
    BenchmarkTools.DEFAULT_PARAMETERS.seconds = BenchmarkTools.DEFAULT_PARAMETERS.samples * time_limit

    @info "Benchmarking matroid constraint (loop method) with Gurobi"
    ps = rand_problem_stream(gurobi, Random.Xoshiro(seed))
    b = @benchmark matroid_constraint_loop(p.ctx, p.M) setup = (p = $ps()) evals = 1
    display(b)
    BenchmarkTools.save("bench/gurobi_loop.json", b)

    @info "Benchmarking matroid constraint (lazy method) with Gurobi"
    ps = rand_problem_stream(gurobi, Random.Xoshiro(seed))
    b = @benchmark matroid_constraint_lazy(p.ctx, p.M) setup = (p = $ps()) evals = 1
    display(b)
    BenchmarkTools.save("bench/gurobi_lazy.json", b)

    @info "Benchmarking matroid constraint (loop method) with GLPK"
    ps = rand_problem_stream(glpk, Random.Xoshiro(seed))
    b = @benchmark matroid_constraint_loop(p.ctx, p.M) setup = (p = $ps()) evals = 1
    display(b)
    BenchmarkTools.save("bench/glpk_loop.json", b)

    @info "Benchmarking matroid constraint (lazy method) with GLPK"
    ps = rand_problem_stream(glpk, Random.Xoshiro(seed))
    b = @benchmark matroid_constraint_lazy(p.ctx, p.M) setup = (p = $ps()) evals = 1
    display(b)
    BenchmarkTools.save("bench/glpk_lazy.json", b)
end

function rand_problem_stream(optimizer, rng::Random.AbstractRNG)
    return function ()
        ctx = init_mip_ctx(rand_profile(rng), optimizer)
        M = rand_matroid(ni(ctx.profile), rng)
        (ctx=ctx, M=M)
    end
end

function rand_profile(rng=Random.default_rng())
    num_agents = rand(rng, 2:10)
    num_items = rand(rng, (num_agents*2):(num_agents*4))
    return Profile(rand(rng, 1:10, num_agents, num_items))
end

function rand_matroid(num_items, rng=Random.default_rng())
    max_edges = div(num_items * (num_items - 1), 2)
    G = SimpleGraph(num_items, rand(rng, 0:max_edges))
    return GraphicMatroid(G)
end

function init_mip_ctx(V::Profile, optimizer)
    return Allocations.init_mip(V, optimizer) |>
           Allocations.achieve_mnw(false)
end

function matroid_constraint_loop(ctx::Allocations.MIPContext, M::Matroid)
    feasible = false

    while !feasible
        try
            ctx = Allocations.solve_mip(ctx)
        catch
            @error "Could not solve the MIP, most likely due to timeout"
            return ctx
        end

        feasible = true
        constraints = Pair[]
        for B in ctx.alloc.bundle
            if !is_indep(M, B)
                feasible = false
                bundle_rank = rank(M, B)
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

function matroid_constraint_lazy(ctx::Allocations.MIPContext, M::Matroid)
    set_attribute(ctx.model, MOI.LazyConstraintCallback(), c -> _matroid_constraint_callback(c, ctx, M))

    try
        Allocations.solve_mip(ctx)
    catch
        @error "Could not solve the MIP, most likely due to timeout"
        return ctx
    end
end

function _matroid_constraint_callback(cb_data, ctx::Allocations.MIPContext, M::Matroid)
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
        if !is_indep(M, B)
            bundle_rank = rank(M, B)
            @debug "Adding cardinality constraint for dependent set: $B => $bundle_rank"
            for i in agents(V)
                con = @build_constraint(sum(ctx.alloc_var[i, g] for g in B) <= bundle_rank)
                MOI.submit(ctx.model, MOI.LazyConstraint(cb_data), con)
            end
        end
    end
end

end # module
