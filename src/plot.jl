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
