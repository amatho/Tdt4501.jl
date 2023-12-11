function init_mip_ctx(V::Profile, optimizer, M::Matroid, ignore_matroid::Bool)
    return Allocations.init_mip(V, optimizer, max_bundle=ignore_matroid ? nothing : rank(M)) |>
           Allocations.achieve_mnw(false)
end

function matroid_constraint_loop(ctx::Allocations.MIPContext, M::Matroid)
    feasible = false

    while !feasible
        try
            ctx = Allocations.solve_mip(ctx)
        catch
            if termination_status(ctx.model) == MOI.TIME_LIMIT
                return ctx
            else
                @error "Could not solve the MIP" termination_status(ctx.model) raw_status(ctx.model)
                rethrow()
            end
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
        if termination_status(ctx.model) == MOI.TIME_LIMIT
            return ctx
        else
            @error "Could not solve the MIP" termination_status(ctx.model) raw_status(ctx.model)
            rethrow()
        end
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

function unconstrained_mnw(ctx::Allocations.MIPContext)
    try
        ctx = Allocations.solve_mip(ctx)
    catch
        if termination_status(ctx.model) == MOI.TIME_LIMIT
            return ctx
        else
            @error "Could not solve the MIP" termination_status(ctx.model) raw_status(ctx.model)
            rethrow()
        end
    end
end
