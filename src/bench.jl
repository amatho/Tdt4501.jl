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

    ps = ProblemStream(opt, Random.Xoshiro(seed), samples)

    if matroid_function == loop
        b = @benchmark matroid_constraint_loop(p.ctx, p.M) setup = (p = iterate($ps)[1]) evals = 1
    else
        b = @benchmark matroid_constraint_lazy(p.ctx, p.M) setup = (p = iterate($ps)[1]) evals = 1
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
    p1 = first(ProblemStream(optimizer, Random.Xoshiro(seed), 1))
    matroid_constraint_loop(p1.ctx, p1.M)
    matroid_constraint_lazy(p1.ctx, p1.M)
    @debug "Warmup finished"
end

function rand_problem(ps::ProblemStream)
    V = rand_profile(ps.rng)
    M = rand_matroid(ni(V), ps.rng)
    ctx = init_mip_ctx(V, ps.optimizer, M)
    ProblemInstance(ctx, M)
end

function rand_profile(rng::Random.AbstractRNG)
    num_agents = rand(rng, 2:10)
    num_items = rand(rng, (num_agents*2):(num_agents*4))
    return Profile(rand(rng, 1:100, num_agents, num_items))
end

function rand_matroid(num_items, rng::Random.AbstractRNG)
    G = SimpleGraph(num_items + 1, num_items, rng=rng)
    return GraphicMatroid(G)
end
