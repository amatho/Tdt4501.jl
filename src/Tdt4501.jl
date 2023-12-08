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
    lazy,
    ProblemInstance,
    ProblemStream,
    rand_problem,
    init_mip_ctx,
    matroid_constraint_loop,
    matroid_constraint_lazy,
    plot_gurobi,
    plot_glpk,
    plot_comparison

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

include("types.jl")
include("mip.jl")
include("bench.jl")
include("plot.jl")

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

end # module
