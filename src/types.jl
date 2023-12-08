@enum OptimizerType gurobi glpk
@enum MatroidFunction loop lazy

struct ProblemInstance
    ctx::Allocations.MIPContext
    M::Matroid
end

struct ProblemStream{T}
    optimizer::T
    rng::Random.AbstractRNG
    length::Int
end

Base.iterate(ps::ProblemStream, state=1) = state > ps.length ? nothing : (rand_problem(ps), state + 1)
Base.eltype(::Type{ProblemStream}) = ProblemInstance
Base.length(ps::ProblemStream) = ps.length
