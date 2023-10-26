module Tdt4501

export test

using Allocations
using Graphs
using HiGHS
using Matroids
import SCIP

function test()
    G = path_graph(3)
    add_edge!(G, 1, 3)

    Matroid = GraphicMatroid(G)
    println(is_indep(Matroid, [1, 2, 3]))
    println("Matroid rank: $(rank(Matroid))")

    V = Profile([2 2 2 1; 1 1 1 2])
    res = alloc_mnw(V)

    for b in res.alloc.bundle
        println("Bundle: $b")
        println("Independent? $(is_indep(Matroid, b))")
    end
end

end
