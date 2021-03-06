#-------------------------------------------------------------------------------
# Set of useful functions related to LOWDEROutput struct.
#-------------------------------------------------------------------------------

"""

    create_output(model::AbstractModel, exit_flag::Symbol, full_calc::Bool,
                    nit::Int64, nf::Int64, δ::Float64, Δ::Float64, π::Float64)

Creates a output for LOWDER algorithm.

    - 'model': model of LinearModel or QuadraticModel type.
    - 'exit_flag': exit flag of algorithm.
    - 'full_calc': boolean that indicates if fmin was calculated for the current 'xopt'.
    - 'nit': number of iterations.
    - 'nf': number of function evaluations.
    - 'δ': sample set radius.
    - 'Δ': trust-region radius.
    - 'π': stationarity measure.

Returns a object of LOWDEROutput type.

"""
function create_output(
                        model::AbstractModel,
                        exit_flag::Symbol,
                        full_calc::Bool,
                        nit::Int64,
                        nf::Int64,
                        δ::Float64,
                        Δ::Float64,
                        π::Float64
                        )

    if ( model.kopt[] == 0 ) || ( full_calc )

        return LOWDEROutput(exit_flag, true, nit, nf, model.imin[], δ, Δ, π, model.fval[1], model.xopt)

    else

        return LOWDEROutput(exit_flag, false, nit, nf, model.imin[], δ, Δ, π, model.fval[ model.kopt[] + 1 ], model.xopt)

    end

end

"""

    show_output(output::LOWDEROutput)

Shows information about the completion of LOWDER execution on the user's screen.

    - 'output': LOWDEROutput object.

"""
function show_output(
                        output::LOWDEROutput
                        )
    
    println("** LOWDER Output **")
    println("Status (.status): $( output.status )" )
    println("Solution (.solution): $( output.solution )" )
    println("Number of iterations (.iter): $( output.iter )" )
    println("Number of function evaluations (.nf): $( output.nf )" )
    println("Stationarity measure (.stationarity): $( output.stationarity )" )
    println("Sample set radius (.sample_radius): $( output.sample_radius ) " )
    println("Trust-region radius (.tr_radius): $( output.tr_radius ) " )
    println("Objective function value (.f): $( output.f )" )
    println("Trusted objective funtion value (.true_val): $( output.true_val )" )
    println("Index of the function (.index): $( output.index )" )

end