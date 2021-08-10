# Turn off precompilation during development
__precompile__(false)

#-------------------------------------------------------------------------------
# Main file implementing LOWDER in Julia
#-------------------------------------------------------------------------------

module LOWDER

    # Load dependencies

    using LinearAlgebra
    using Printf

    # Load code
    include("lovo_utils.jl")
    include("utils.jl")
    include("linear_models.jl")

    function lowder(
                    func_list::Array{Function,1},
                    x::Vector{Float64},
                    a::Vector{Float64}, 
                    b::Vector{Float64},
                    δ::Float64,
                    Δ::Float64;
                    m::Int64=(2 * length(x) + 1),
                    maxit::Int64=5000,
                    maxfun::Int64=(1000 * (length(func_list) + m)),
                    Γmax::Int64=1,
                    δmin::Float64=1.0e-8,
                    πmin::Float64=1.0e-8,
                    β::Float64=1.0,
                    τ1::Float64=0.6,
                    τ2::Float64=1.5,
                    τ3::Float64=2.0,
                    η::Float64=0.1,
                    η1::Float64=0.3,
                    η2::Float64=0.6,
                    verbose::Bool=true
                    )

        # Calculates the search space dimension.
        n = length(x)

        # Calculates the number of functions that make up the objective function fmin
        r = length(func_list)

        # Verify algorithm initialization conditions.
        m_min = n + 2
        m_max = convert(Int64, ( n + 1 ) * ( n + 2 ) / 2)
        @assert m_min ≤ m ≤ m_max "The number of interpolation points 'm' must satisfy m ∈ [$(m_min), $(m_max)]."
        @assert length(a) == n "The vector 'a' must have dimension $(n)."
        @assert length(b) == n "The vector 'b' must have dimension $(n)."
        @assert 0.0 < δ ≤ Δ "The radius of the sample set 'δ' must be positive and less or equal to the trust-region radius 'Δ'."
        @assert verify_initial_room(n, δ, a, b) "The radius of the initial sample set 'δ' is not suitable, it must satisfy a[i]- b[i] >= 2δ, for i = 1, ..., $(n)."
        @assert maxit > 0 "The parameter 'maxit' must be positive."
        @assert maxfun ≥ r "The parameter 'maxfun' must be greater than ou equal to $(r)."
        @assert Γmax > 0 "The parameter 'Γmax' must be positive."
        @assert δmin > 0.0 "The parameter 'δmin' must be positive."
        @assert β > 0.0 "The parameter 'β' must be positive."
        @assert 0.0 < τ1 < 1.0 "The parameter 'τ1' must be positive and less than one."
        @assert 1.0 ≤ τ2 "The parameter 'τ2' must be greater than or equal to one."
        @assert τ2 ≤ τ3 "The parameter 'τ3' must be greater than or equal to 'τ2'."
        @assert 0.0 < η1 < 1.0 "The parameter 'η1' must be positive and less than one."
        @assert 0 ≤ η < η1 "The parameter 'η' must be nonnegative and less than 'η1'."
        @assert η1 ≤ η2 "The parameter 'η2' must be greater than or equal to 'η1'."
        
        # Sets some useful constants.
        Δinit = Δ
        nh = convert(Int64, n * ( n + 1 ) / 2)

        # Initializes useful variables, vectors, and matrices.
        countit = 0                 # Counts the number of iterations.
        countf = 0                  # Counts the number of 'f_i' function evaluations.
        Γ = 0                       # Auxiliary counter for Radii adjustments phase.
        xbase = zeros(n)            # Origin of the sample set.
        xopt = zeros(n)             # Point with the smallest objective function value.
        ao = zeros(n)               # Difference between the lower bounds 'a' and the center of the sample set, given by 'xbase'.
        bo = zeros(n)               # Difference between the upper bounds 'b' and the center of the sample set, given by 'xbase'.
        fval = zeros(m)             # Set of the function values of the interpolation points.
        gopt = zeros(n)             # Holds the gradient of the quadratic model at 'xbase + xopt'
        hq = zeros(nh)              # Holds the explicit second derivatives of the quadratic model.
        pq = zeros(m)               # Holds parameters of the implicit second derivatives of the quadratic model.
        Y = zeros(n, m)             # Set of interpolation points, shifted from the center of the sample set 'xbase'.
                                        # 'Y = [y1 | y2 | y3 | ... | ym]'.
        BMAT = zeros(m + n, n)      # Holds the elements of 'Ξ', with the exception of its first column, 
                                        # and the elements of 'Υ', with the exception of its first row and column. 
        ZMAT = zeros(m, m - n - 1)  # Holds the elements of 'Z', from the factorization 'Ω = ZZ^T'.

        #-------------------- Preparations for the first iteration ---------------------

        # Modifies the initial estimate 'x' to be suitable for building the first model. 
        # Modifies 'ao' and 'bo' to store the 'a-xbase' and 'b-xbase' differences, respectively.
        correct_guess_bounds!(n, δ, a, b, x, ao, bo)

        # Saves the origin of the sample set in 'xbase'. Vector 'x' will be used as workspace.
        copyto!(xbase, x)

        # Computes the value of f_min at 'xbase' and an index 'imin' belonging to the set I_min(xbase).
        fbase, imin = fmin_eval(func_list, r, xbase)

        # Updates de function call counter.
        countf += r

        # Builds the initial sample set 'Y', calculates the respective function values 'fval', updates de function call counter 'countf',
        # determines the elements of 'gopt', 'hq', 'BMAT', and 'ZMAT', and the point with the smallest function value 'xopt'.
        # Defines 'kopt' as the position of 'xopt' in set 'Y'.
        kopt, countf = construct_initial_set!(func_list, n, m, imin, maxfun, fbase, δ, a, b, ao, bo, xbase, countf, xopt, fval, gopt, hq, BMAT, ZMAT, Y, x)

        # Defines 'kbase' as the position of 'xbase' in set 'Y', i.e., 'kbase' is set to 1.
        kbase = 1

        # Saves the objective function value at 'xbase' in
        fsave = fbase

        # Returns if 'countf' exceeds 'maxfun'.
        if countf ≥ maxfun

            it_flag = 0
            exit_flag = -2

            # Prints information about the iteration.
            if verbose
                print_iteration(countit, countf, it_flag, δ, Δ, fsave)
            end

            # Prints information about the exit flag.
            print_info(exit_flag)

            # Prints additional information
            if kopt != kbase
                add_exit_flag = -11
                print_info(add_exit_flag)
            end
            
            return xbase, fsave, imin, countit, countf, δ, Δ, it_flag, exit_flag, xopt, fval[kopt]
            
        end
        
        # Updates 'gopt', if necessary.
        if kopt != kbase
            update_gopt!(n, m, r, countf, xopt, hq, pq, Y, gopt)
        end

        while true

            δold = δ
            Δold = Δ

            π = stationarity_measure(n, a, b, xopt, gopt)

            # Verifies if 'δ' and 'π' are less than or equal to 'δmin' and 'πmin', respectively.
            if ( δ ≤ δmin ) && ( π ≤ πmin )
                exit_flag = 1
                break
            end

            if δ > β * π
                #------------------------------ Criticality phase ------------------------------

                it_flag = 1

                # Update parameters
                δ *= τ1
                ρ = 0.0

            else

                #------------------------------- Step acceptance -------------------------------

                ### Verificar se a direção é de descida para o modelo.

                ### Calcular ρ.

                if ρ ≥ η
                    ### Atualizar o ponto e remover o ponto indicado pelo TRSBOX.
                else
                    ### Calcular a nova direção via ALTMOV e remover o ponto indicado.
                end

                #------------------------------- Radii updates ---------------------------------

                if ρ < η1
                    δ *= τ1
                    Δ *= τ1
                elseif ( ρ > η2 ) && ( norm(d) == Δ )
                    δ *= τ2
                    Δ *= τ2
                end

            end

            # Prints information about the iteration.
            if verbose
                print_iteration(countit, countf, it_flag, δold, Δold, fsave)
            end

            #------------------------- Verifies output conditions --------------------------
        
            # Verifies if 'countit' exceeds 'maxit'.
            if countit ≥ maxit
                exit_flag = -1
                break
            end

            # Verifies if 'countf' exceeds 'maxfun'.
            if countf ≥ maxfun
                exit_flag = -2
                break
            end

            #--------------------------- Radii adjustments phase ---------------------------
            
            if ρ ≥ η
                ### Escolha i \in Imnin(x_{k+1})
                if i != imin

                    imin = i

                    if ρ ≥ η1

                        Γ = 0

                    end

                    if Γ ≤ Γmax

                        # Adjusts the radii to create a new model.
                        δ = τ3 * δold
                        Δ = max( τ3 * Δold, Δinit )
                        Γ += 1

                    end
                    ### Construir um novo modelo

                else
                    ### imin não é alterado
                    ### Atualizar o modelo
                    ### RESCUE?
                end

            else
                ### imin não é alterado
                ### Atualizar o modelo
                ### RESCUE?
            end

            # Increases iteration counter
            countit += 1

        end

        #---------------------- Preparations to finish execution  ----------------------

        # Prints information about the exit flag.
        print_info(exit_flag)

        # Prints additional information
        if kopt != kbase
            add_exit_flag = -12
            print_info(add_exit_flag)
        end

        return x, fsave, imin, countit, countf, δ, Δ, it_flag, exit_flag, xopt, fval[kopt]

    end

end
