module Tdt4501

export bench_all,
    bench,
    plot_gurobi,
    plot_glpk,
    plot_comparison,
    OptimizerType,
    gurobi,
    glpk,
    MatroidFunction,
    loop,
    lazy

using Allocations
using BenchmarkPlots
using BenchmarkTools
import GLPK
using Graphs
import Gurobi
using JuMP
import Logging
using Matroids
import Random
using StatsPlots
using Unitful

@enum OptimizerType gurobi glpk
@enum MatroidFunction loop lazy

const GRB_ENV_REF = Ref{Gurobi.Env}()
const epsilon = 1e-5
const check_allocation = check_partition
const time_limit = 300

function __init__()
    global GRB_ENV_REF
    GRB_ENV_REF[] = Gurobi.Env()

    debug_logger = Logging.ConsoleLogger(Logging.Info)
    Logging.global_logger(debug_logger)

    return
end

function plot_gurobi()
    gurobi_loop = first(BenchmarkTools.load("bench/gurobi_loop.json"))
    gurobi_lazy = first(BenchmarkTools.load("bench/gurobi_lazy.json"))

    p = palette(:default)
    boxplot(gurobi_loop.times * u"ns", yunit=u"ms", yscale=:log10, ylabel="time", color=p[1], legend=false)
    boxplot!(gurobi_lazy.times * u"ns", color=p[2])
    xticks!([1, 2], ["Gurobi Loop", "Gurobi Lazy"])
end

function plot_glpk()
    glpk_loop = first(BenchmarkTools.load("bench/glpk_loop.json"))
    glpk_lazy = first(BenchmarkTools.load("bench/glpk_lazy.json"))

    p = palette(:default)
    boxplot(glpk_loop.times * u"ns", yunit=u"ms", yscale=:log10, ylabel="time", color=p[3], legend=false)
    boxplot!(glpk_lazy.times * u"ns", color=p[4])
    xticks!([1, 2], ["GLPK Loop", "GLPK Lazy"])
end

function plot_comparison()
    gurobi_loop = first(BenchmarkTools.load("bench/gurobi_loop.json"))
    gurobi_lazy = first(BenchmarkTools.load("bench/gurobi_lazy.json"))
    glpk_loop = first(BenchmarkTools.load("bench/glpk_loop.json"))
    glpk_lazy = first(BenchmarkTools.load("bench/glpk_lazy.json"))

    p = palette(:default)
    boxplot(gurobi_loop.times * u"ns", yunit=u"ms", yscale=:log10, ylabel="time", color=p[1], legend=false)
    boxplot!(gurobi_lazy.times * u"ns", color=p[2])
    boxplot!(glpk_loop.times * u"ns", color=p[3])
    boxplot!(glpk_lazy.times * u"ns", color=p[4])
    xticks!([1, 2, 3, 4], ["Gurobi Loop", "Gurobi Lazy", "GLPK Loop", "GLPK Lazy"])
end

function bench_all(; seed=nothing, save=true, samples=1000)
    if isnothing(seed)
        seed = rand(UInt)
    end
    @info "Running all benchmarks" seed = string(seed) save samples
    bench(gurobi, loop, seed=seed, save=save, samples=samples)
    bench(gurobi, lazy, seed=seed, save=save, samples=samples)
    bench(glpk, loop, seed=seed, save=save, samples=samples)
    bench(glpk, lazy, seed=seed, save=save, samples=samples)
end

function bench(optimizer_type::OptimizerType, matroid_function::MatroidFunction; seed=nothing, save=true, samples=1000)
    if isnothing(seed)
        seed = rand(UInt)
    end
    @info "Benchmarking matroid constraint ($matroid_function method) with $(titlecase(string(optimizer_type)))" seed = string(seed) save samples

    if optimizer_type == glpk
        opt = optimizer_with_attributes(GLPK.Optimizer, "tm_lim" => time_limit * 1_000)
    else
        opt = optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV_REF[]), "LogToConsole" => 0, "TimeLimit" => time_limit)
    end

    warmup(opt)

    BenchmarkTools.DEFAULT_PARAMETERS.seconds = samples * time_limit
    BenchmarkTools.DEFAULT_PARAMETERS.samples = samples

    ps = rand_problem_stream(opt, Random.Xoshiro(seed))
    if matroid_function == loop
        b = @benchmark matroid_constraint_loop(p.ctx, p.M) setup = (p = $ps()) evals = 1
    else
        b = @benchmark matroid_constraint_lazy(p.ctx, p.M) setup = (p = $ps()) evals = 1
    end

    display(b)

    if save
        path = "bench/$(optimizer_type)_$(matroid_function).json"
        @info "Saving benchmark trial to $path"
        BenchmarkTools.save(path, b)
    end
end

function warmup(optimizer)
    seed = 42424242
    @debug "Warming up..."
    p1 = rand_problem_stream(optimizer, Random.Xoshiro(seed))()
    matroid_constraint_loop(p1.ctx, p1.M)
    matroid_constraint_lazy(p1.ctx, p1.M)
    @debug "Warmup finished"
end

function rand_problem_stream(optimizer, rng::Random.AbstractRNG)
    return function ()
        V = rand_profile(rng)
        M = rand_matroid(ni(V), rng)
        ctx = init_mip_ctx(V, optimizer, M)
        (ctx=ctx, M=M)
    end
end

function rand_profile(rng::Random.AbstractRNG)
    num_agents = rand(rng, 2:10)
    num_items = rand(rng, (num_agents*2):(num_agents*4))
    return Profile(rand(rng, 1:100, num_agents, num_items))
end

function rand_matroid(num_items, rng::Random.AbstractRNG)
    max_edges = div(num_items * (num_items - 1), 2)
    G = SimpleGraph(num_items, rand(rng, 3:max_edges))
    return GraphicMatroid(G)
end

function init_mip_ctx(V::Profile, optimizer, M::Matroid)
    return Allocations.init_mip(V, optimizer) |> # TODO: Add rank of matroid as max bundle size
           Allocations.achieve_mnw(false)
end

function matroid_constraint_loop(ctx::Allocations.MIPContext, M::Matroid)
    feasible = false

    while !feasible
        try
            ctx = Allocations.solve_mip(ctx)
        catch error
            @error "Could not solve the MIP, most likely due to timeout" error termination_status(ctx.model) raw_status(ctx.model)
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
            A = ctx.alloc_var
            for i in agents(V)
                con = @build_constraint(sum(A[i, g] for g in B) <= bundle_rank)
                MOI.submit(ctx.model, MOI.LazyConstraint(cb_data), con)
            end
        end
    end
end

end # module
