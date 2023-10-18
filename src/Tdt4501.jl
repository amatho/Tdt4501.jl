module Tdt4501

using JuMP
using HiGHS

greet() = "Hello World!"

function test()
    model = Model(HiGHS.Optimizer)
    @variable(model, x >= 0)
    @variable(model, 0 <= y <= 3)
    @objective(model, Min, 12x + 20y)
    @constraint(model, c1, 6x + 8y >= 100)
    @constraint(model, c2, 7x + 12y >= 120)
    println(model)
    optimize!(model)
end

export greet

end
