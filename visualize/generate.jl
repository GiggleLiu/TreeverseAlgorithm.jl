using TreeverseAlgorithm

function generate_log(N, δ; filename=nothing)
    logger = TreeverseLog()
    treeverse(x->0.0, (x,z)->0.0, 0.0; N=N, δ=δ,logger=logger)
    if filename !== nothing
        dumplog(logger, filename)
    end
    return logger
end

logger = generate_log(30, 5, filename=joinpath(@__DIR__, "treeverse-30-5.json"))