using Allocations
import GLPK
using Graphs
using Matroids
import Random
using Tdt4501
using Test

@testset "Tdt4501" begin
    @testset "problem generation" begin
        # Test that the same problems are generated when using the same seed
        optimizer = GLPK.Optimizer
        seed = rand(UInt)
        ps = ProblemStream(optimizer, Random.Xoshiro(seed), 50)
        p1 = collect((p.ctx.profile.values, p.M.g) for p in ps)
        ps = ProblemStream(optimizer, Random.Xoshiro(seed), 50)
        p2 = collect((p.ctx.profile.values, p.M.g) for p in ps)
        ps = ProblemStream(optimizer, Random.Xoshiro(seed), 50)
        p3 = collect((p.ctx.profile.values, p.M.g) for p in ps)
        ps = ProblemStream(optimizer, Random.Xoshiro(seed), 50)
        p4 = collect((p.ctx.profile.values, p.M.g) for p in ps)

        @test p1 == p2 && p2 == p3 && p3 == p4
    end
    
    @testset "matroid constraints" begin
        # Test correctness of matroid constraint methods
        # Profile is designed to give agents dependent bundles when ran without matroid constraints.
        # Unconstrained MNW will give the agents bundles (1, 2, 3) and (4, 5, 6).
        V = Profile([10 10 10 1 1 1; 1 1 1 10 10 10])
        # Construct graphic matroid with two circuits (1, 2, 3) and (4, 5, 6)
        G = SimpleGraph(6)
        add_edge!(G, 1, 2)
        add_edge!(G, 2, 3)
        add_edge!(G, 3, 1)
        add_edge!(G, 4, 5)
        add_edge!(G, 5, 6)
        add_edge!(G, 6, 4)
        M = GraphicMatroid(G)

        ctx = init_mip_ctx(V, GLPK.Optimizer, M)
        ctx = matroid_constraint_loop(ctx, M)
        println(ctx.alloc.bundle)
        indep_bundles = [is_indep(M, B) for B in ctx.alloc.bundle]
        @test all(indep_bundles)

        ctx = init_mip_ctx(V, GLPK.Optimizer, M)
        ctx = matroid_constraint_lazy(ctx, M)
        indep_bundles = [is_indep(M, B) for B in ctx.alloc.bundle]
        @test all(indep_bundles)
    end
end
