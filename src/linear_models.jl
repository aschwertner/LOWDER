#-------------------------------------------------------------------------------
# Set of useful functions related to LinearModel struct.
#-------------------------------------------------------------------------------

"""

    create_linear_model(n::Int64)

Creates a empty LinearModel object.

    - 'n': dimension of the search space.

Returns a model of LinearModel type.

"""
function create_linear_model(
                                n::Int64
                            )

    return LinearModel(n, n + 1, Ref{Int64}(), Ref{Int64}(), Ref{Float64}(), zeros(Float64, n), zeros(Float64, n), zeros(Float64, n), zeros(Float64, n + 1), zeros(Float64, n), zeros(Float64, n, n))

end

"""

    construct_model!(func_list::Array{Function, 1}, imin_idx::Int64, 
                        δ::Float64, fbase::Float64, xbase::Vector{Float64},
                        ao::Vector{Float64}, bo::Vector{Float64},
                        model::LinearModel)

Constructs the model based in the given information.

    - 'func_list': list containing the functions that determine the objective
    function fmin.

    - 'imin_idx': index belonging to the set I_{min}('xbase').

    - 'δ': radius of the sample set.

    - 'fbase': objective function value in 'xbase'.

    - 'xbase': n-dimensional vector (origin of the sample set).

    - 'ao': n-dimensional vector with the shifted lower bounds.

    - 'bo': n-dimensional vector with the shifted upper bounds.

The function modifies the argument:

    - 'model': model of LinearModel type.

"""
function construct_model!(
                            func_list::Array{Function, 1},
                            imin_idx::Int64, 
                            δ::Float64, 
                            fbase::Float64,
                            xbase::Vector{Float64},
                            ao::Vector{Float64},
                            bo::Vector{Float64},
                            model::LinearModel
                            )

    # Saves information about the index i ∈ I_{min}('xbase') and f_{i}('xbase').
    model.imin[] = imin_idx
    model.fval[1] = fbase

    kopt = 1
    for i = 1:model.n

        # Saves information about 'model.xbase' and 'model.xopt'.
        model.xbase[i] = xbase[i]
        model.xopt[i] = xbase[i]

        # Constructs the set interpolation points 'model.Y', shifted from 'xbase'.
        if bo[i] == 0.0
            model.Y[i, i] = - δ
        else
            model.Y[i, i] = δ
        end

        # Saves the distance between the i-th point in 'model.Y' and 'model.xbase'.
        model.dst[i] = δ

        # Evaluates the function values and saves the information in 'model.fval'.
        xbase[i] += α
        model.fval[i + 1] = fi_eval(func_list, imin, xbase)
        xbase[i] -= α

        # Searches for the least function value to determine 'kopt'.
        if model.fval[i + 1] < fbase
            kopt = i + 1
            fbase = model.fval[i + 1]
        end

    end

    # Saves the index of the best point in 'model.kopt'
    model.kopt[] = kopt

    # If the best point is not 'xbase', updates the vector 'xopt' and saves the information in 'model.xopt'.
    # Also updates the vector of 'model.dst', to store the distance between the interpolation points and 'xopt'.
    # Note that in the 'kopt' position of the 'model.dst' vector we keep the distance between 'xbase' and 'xopt' points. 
    if kopt != 1

        model.xopt[kopt - 1] += model.Y[kopt - 1, kopt - 1]

        @. model.dst *= srqt(2.0)
        model.dst[kopt] = δ

    end

    # Solves the system to determine the gradient of the linear model 'model.g'
    model.g = model.Y \ ( model.fval[2:end] .- model.fval[1] )

    # Determines the constant of the linear model 'model.c'
    model.c[] = model.fval[1] - dot( model.g, model.xbase )

end

"""

    stationarity_measure(model::LinearModel, a::Vector{Float64}, 
                            b::Vector{Float64})

Calculates the stationarity measure π_{k} = || P_{Ω}( x_{k} - g_{k} ) - x_{k} ||.

    - 'model': model of LinearModel type. 

    - 'a': n-dimensional vector with the lower bounds.

    - 'b': n-dimensional vector with the upper bounds.

Returns the stationarity measure.

"""
function stationarity_measure(
                                model::LinearModel,
                                a::Vector{Float64}, 
                                b::Vector{Float64}
                                )

    aux = 0.0
    for i = 1:model.n
        aux += ( min( max( a[i], model.xopt[i] - model.g[i] ), b[i] ) - model.xopt[i] ) ^ 2.0
    end

    return sqrt(aux)

end

( model::LinearModel )( x::AbstractVector ) = model.c + dot( model.g, x )

∇( model::LinearModel )( x::AbstractVector ) = model.g

∇2( model::LinearModel )( x::AbstractVector ) = false * I

function update_model!(
                        model::LinearModel, 
                        t::Int64,
                        fval_d::Float64,
                        d::Vector{Float64}
                        )

    # Updates Y set.
    for i = 1:model.n
        @. model.Y[i, :] -= d
    end

    # Puts the old xbase in the t-th vector in Y.
    @. model.Y[t, :] =  - d
    model.fval[t + 1] = model.fval[1]

    # Updates the distance vector.
    for i = 1:model.n
        model.dst[i] = norm(model.Y[i, :])
    end

    # Adds the new center.
    model.fval[1] = fval_d
    @. model.xbase += d 

    return rebuild_model!(model)

end

function model_from_scratch!(
                                model::LinearModel,
                                func_list::Array{Function, 1}, 
                                δ::Float64,
                                b::Vector{Float64}
                                )

    # Sets Y to a empty matrix.
    @. model.Y = 0.0

    for i = 1:model.n
        
        # Computes the new interpolation points and the distances.
        α = min( b[i] - model.xbase[i], δ )
        model.Y[i, i] = α
        model.dst[i] = α

        # Computes the function values.
        model.xbase[i] += α
        model.fval[i + 1] = func_list[model.imin](model.xbase)
        model.xbase[i] -= α

    end

    return rebuild_model!(model)

end

function rebuild_model!(
                        model::LinearModel
                        )

    # Computes the new c and g.
    # !!! Very inefficient !!!

    model.g = model.Y \ ( model.fval[2:end] .- model.fval[1] )
    model.c = model.fval[1] - dot( model.g, model.xbase )

    return LinearModel(model.n, model.imin, model.c, model.g, model.xbase, model.fval, model.dst, model.Y )

end

function compute_active_set!(
                        model::LinearModel,
                        ao::Vector{Float64},
                        bo::Vector{Float64},
                        active_set::Vector{Bool}
                        )
    for i=1:model.n
        if ( model.Y[model.kopt, i] == ao[i] && model.g[i] >= 0.0 ) || ( model.Y[model.kopt, i] == bo[i] && model.g[i] <= 0.0 )
            active_set[i] = true
        else
            active_set[i] = false
        end
    end

end

function trsbox!(
                    model::LinearModel,
                    Δ::Float64,
                    ao::Vector{Float64},
                    bo::Vector{Float64},
                    active_set::Vector{Bool},
                    x::Vector{Float64},
                    d::Vector{Float64}
                    )
    
    # Copies the shifted vector 'xopt' to 'x'.
    copyto!(x, model.Y[model.kopt, :])

    # Creates the active constraint vector 'active_set'.
    compute_active_set!(model, ao, bo, active_set)

    # Computes the symmetric vector of the projection of the 
    # gradient of the model by the set of active constraints.
    projection_active_set!(model.g, active_idx, d, sym = true)

    # If the set of active constraints is not complete,
    # calculates step 'd' and updates point 'x'.
    if sum(active_set) != model.n
        α = Inf
        α_B = Inf
        α_Δ = Δ / norm(d)

        for i=1:model.n
            if d[i] > 0.0
                α = ( bo[i] - model.Y[model.kopt[], i] ) / d[i]
            elseif d[i] < 0.0
                α = ( ao[i] - model.Y[model.kopt[], i] ) / d[i]
            end
            if α < α_B
                α_B = α
            end
        end

        if α_Δ ≤ α_B
            @. d *= α_Δ
        else
            @. d *= α_B
        end

        @. x += d

    end
    
end

function choose_index_trsbox(
                                model::LinearModel,
                                Δ::Float64,
                                xnew::Vector{Float64}
                                )
    
    d_base = xnew - model.xbase
    e_t = zeros(model.n)
    sol_t = zeros(model.n)
    qrY = qr(model.Y, Val(true))
    α = - Inf

    for i=1:model.n
        if i != model.kopt[]
            e_t[i] = 1.0

            ldiv!(sol_t, qrY, e_t)

            α_t = max( 1.0, ( model.dst[i] / Δ ) ^ 2.0 ) * ( 1.0 + dot(d_base, sol_t) )

            if α_t > α
                α = α_t
                t = i
            end

            e_t[i] = 0.0
        end
    end

    return t

end

function choose_index_altmov(
                                model::LinearModel
                            )
    
    ( val, idx_t ) = findmin(model.dst)

    if idx_t == model.kopt[]
        idx_t = 0
    end

    return idx_t

end

function Λ_t(
                model::LinearModel,
                idx_t::Int64,
                y::Vector{Float64},
                qrY::QRPivoted{Float64, Matrix{Float64}}
                )

    if idx_t == 0

        e = - ones(Float64, model.n)
        sol = zeros(Float64, model.n)
        ldiv!(sol, qrY, e)

        return 1.0 + dot(y - model.xbase, sol)

    else

        e_t = zeros(Float64, model.n)
        e_t[idx_t] = 1.0
        sol = zeros(Float64, model.n)
        ldiv!(sol, qrY, e_t)

        return dot(y - model.xbase, sol)

    end

end

function altmov!(
                    model::LinearModel,
                    idx_t::Int64,
                    ao::Vector{Float64},
                    bo::Vector{Float64},
                    x::Vector{Float64},
                    d::Vector{Float64},
                    altmov_set::Vector{Bool}
                    )

    qrY = qr(model.Y, Val(true))
    best_abs_ϕ = - 1.0

    # Calculates the "Usual" Alternative Step
    for j = 1:model.n

        # Uses 'd' as a workspace to save the difference between the 
        # i-th interpolation point and 'xopt'. In the case where 'i' = 'kopt',
        # 'd' holds the difference between 'xbase' and 'xopt'. 
        if j == model.kopt[]
            @. d = - model.Y[model.kopt, :]
        else
            @. d = model.Y[j, :] - model.Y[model.kopt[], :]
        end

        # Gets the bounds for α_{j} relative to the trust-region.
        α_upper = Δ / model.dst[j]
        α_lower = - α_upper

        # Adjusts the bounds to the box constraints.
        for i = 1:model.n
            if d[i] > 0.0
                α_lower = max( α_lower, ( ao[i] - model.xopt[i] ) / d[i] )
                α_upper = min( α_upper, ( bo[i] - model.xopt[i] ) / d[i] )
            elseif d[i] < 0.0
                α_lower = min( α_lower, ( bo[i] - model.xopt[i] ) / d[i] )
                α_upper = max( α_upper, ( ao[i] - model.xopt[i] ) / d[i] )
            end
        end

        # Since the Lagrange polynomial is linear, the optimal α is either lower or upper value.
        # Uses 'x' as a workspace to hold 'xopt + α * (y_{j} - xopt)'
        @. x = model.xopt + α_lower * d
        ϕ_lower = Λ_t(model, idx_t, x, qrY)
        @. x = model.xopt + α_upper * d
        ϕ_upper = Λ_t(model, idx_t, x, qrY)

        if abs(ϕ_lower) > abs(ϕ_upper)
            α_j = α_lower
            abs_ϕ_j = abs(ϕ_lower)
        else
            α_j = α_upper
            abs_ϕ_j = abs(ϕ_upper)
        end

        # Compares the best ϕ_j value so far
        if abs_ϕ_j > best_abs_ϕ

            best_abs_ϕ = abs_ϕ_j
            best_idx = j
            best_α

        end

    end

    # Calculates the "Cauchy" Alternative Step

    if idx_t == 0

        e = - ones(Float64, model.n)
        ∇Λ_t = zeros(Float64, model.n)
        ldiv!(∇Λ_t, qrY, e)

    else

        e_t = zeros(Float64, model.n)
        e_t[idx_t] = 1.0
        ∇Λ_t = zeros(Float64, model.n)
        ldiv!(∇Λ_t, qrY, e_t)

    end

    Λ_1 = altmov_cauchy!(model, idx_t, Δ, ∇Λ_t, ao, bo, d, altmov_set)
    Λ_2 = altmov_cauchy!(model, idx_t, Δ, ∇Λ_t, ao, bo, x, altmov_set, sym = true)

    ( val, idx ) = findmax( [ best_abs_ϕ, Λ_1, Λ_2 ] )

    if idx == 1

        @. x = model.xopt + best_α * ( model.Y[ best_idx, : ] - model.Y[ model.kopt[], : ] )

    elseif idx == 2

        @. x = model.Y[ model.kopt[], :] + d

    else

        @. x += model.Y[ model.kopt[], : ]

    end

    return idx

end

function altmov_cauchy!(
                        model::LinearModel,
                        idx_t::Int64,
                        Δ::Float64,
                        ∇Λ_t::Vector{Float64},
                        ao::Vector{Float64},
                        bo::Vector{Float64},
                        s::Vector{Float64},
                        active_set::Vector{Float64};
                        sym::Bool=false
                        )

    z = zeros(Float64, model.n)

    if sym
        p = 1.0
    else
        p = 2.0
    end

    norm2_s = 0.0
    for i = 1:model.n
        if ( (- 1.0) ^ p ) * ∇Λ_t[i] > 0.0
            s[i] = ao[i] - model.xopt[i]
            norm2_s += s[i] ^ 2.0
        elseif ( (- 1.0) ^ p ) * ∇Λ_t[i] < 0.0
            s[i] = bo[i] - model.xopt[i]
            norm2_s += s[i] ^ 2.0
        else
            s[i] == 0.0
        end
    end

    if norm2_s ≤ ( Δ ^ 2.0 )

        @. z = model.Y[model.kopt[], :] + s

        if idx_t == 0
            return abs( 1.0 + dot(z, ∇Λ_t) )
        else
            return abs( dot(z, ∇Λ_t) )
        end

    end

    # Saves a copy of 's' in 'z'.
    copyto!(z, s)
    
    sum_free = 0.0
    sum_fixed = 0.0
    for i = 1:model.n

        if s[i] != 0.0

            sum_free += ∇Λ_t[i] ^ 2.0
            active_set[i] = false

        else

            active_set[i] = true

        end

    end

    if sum_free == 0.0

        s .= 0.0
        return 0.0

    end

    while true

        num_μ = Δ ^ 2.0 - sum_fixed

        if num_μ > 0.0

            μ = sqrt( num_μ / sum_free )

            stop = true
            sum_free = 0.0
            sum_fixed = 0.0

            for i = 1:model.n

                if active_set[i]

                    s[i] = z[i]
                    sum_fixed += z[i] ^ 2.0

                else

                    s[i] = ( (- 1.0) ^ ( p + 1 ) ) * μ * ∇Λ_t[i]

                    step_i = s[i] + model.xopt[i]

                    if ( step_i < ao[i] ) || ( step_i > bo[i] )
                    
                        stop = false
                        active_set[i] = true
                        sum_fixed += z[i] ^ 2.0

                    else

                        sum_free += ∇Λ_t[i] ^ 2.0

                    end
                end
            end

            if stop || ( sum_free == 0.0 )

                break

            end

        else

            break

        end

    end

    @. z = model.Y[model.kopt[], :] + s

    if idx_t == 0

        return abs( 1.0 + dot(z, ∇Λ_t) )

    else

        return abs( dot(z, ∇Λ_t) )

    end

end