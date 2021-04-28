module TreeverseAlgorithm

using Requires

include("treeverse.jl")

function __init__()
    @require Viznet = "52a3aca4-6234-47fd-b74a-806bdf78ede9" begin
        include("visualize.jl")
    end
end

end
