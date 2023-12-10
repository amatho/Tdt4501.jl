@enum OptimizerType gurobi glpk
@enum MatroidFunction loop lazy

struct ProblemInstance
    ctx::Allocations.MIPContext
    M::Matroid
end

struct ProblemStream
    optimizer
    rng::Random.AbstractRNG
    length::Int
    log_each::Union{Int,Nothing}
    ProblemStream(optimizer, rng, length, log_each=nothing) = new(optimizer, rng, length, log_each)
end

function Base.iterate(ps::ProblemStream, state=1)
    if state > ps.length
        nothing
    else
        if !isnothing(ps.log_each) && state % ps.log_each == 0
            @info "Generating problem number $state"
        end
        (rand_problem(ps), state + 1)
    end
end
Base.eltype(::Type{ProblemStream}) = ProblemInstance
Base.length(ps::ProblemStream) = ps.length
