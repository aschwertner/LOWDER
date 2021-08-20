struct LOWDEROutput
   
    iter       :: Int64
    index      :: Int64
    nf         :: Int64
    status     :: Int64
    true_val   :: Bool
    f          :: Float64
    solution   :: Vector{Float64}

end

function create_output(
                        model::AbstractModel,
                        nit::Int64,
                        nf::Int64,
                        exit_flag::Int64
                        )

    if model.kopt[] == 1
        return LOWDEROutput(nit, model.imin[], nf, exit_flag, true, model.fval[1], model.xbase)
    else
        return LOWDEROutput(nit, model.imin[], nf, exit_flag, false, model.fval[model.kopt[]], model.xopt)
    end

end

function show_output(
                        output::LOWDEROutput
                        )
    
    println("** LOWDER Output **")
    println("Status (.status): ", $(output.status))
    println("Solution (.solution): ", $(output.solution))
    println("Number of iterations (.iter): ", $(output.iter))
    println("Number of function evaluations (.nf): ", $(output.nf))
    println("Objective function value (.f): ", $(output.f))
    println("Trusted objective funtion value (.true_val): ", $(output.true_val))
    println("Index of the function (.index): ", $(output.index))

end