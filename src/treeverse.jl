struct TreeverseAction
    action::Symbol
    τ::Int
    δ::Int
    step::Int
    depth::Int
end

struct TreeverseLog
    actions::Vector{TreeverseAction}
    depth::Base.RefValue{Int}
    peak_mem::Base.RefValue{Int}  # should be `n*(k-1)+2`
end
TreeverseLog() = TreeverseLog(TreeverseAction[], Ref(0), Ref(0))
Base.push!(tlog::TreeverseLog, args...) = push!(tlog.actions, TreeverseAction(args..., tlog.depth[]))

Base.show(io::IO, ::MIME"text/plain", logger::TreeverseLog) = Base.show(io, logger)
function Base.show(io::IO, logger::TreeverseLog)
    print(io, """Treeverse log
| peak memory usage = $(logger.peak_mem[])
| number of function calls = $(count(x->x.action==:call, logger.actions))
| number of gradient calls = $(count(x->x.action==:grad, logger.actions))
| number of stack push/pop = $(count(x->x.action==:store, logger.actions))/$(count(x->x.action==:fetch, logger.actions))""")
end

"""
    dumplog(logger::TreeverseLog, filename::String)

Dump the TreeverseLog to a JSON file using JSON3.
"""
function dumplog(logger::TreeverseLog, filename::String)
    # Convert RefValue to actual values for serialization
    data = Dict(
        "actions" => logger.actions,
        "depth" => logger.depth[],
        "peak_mem" => logger.peak_mem[]
    )
    
    open(filename, "w") do io
        JSON3.write(io, data)
    end
end

"""
    loadlog(filename::String)

Load a TreeverseLog from a JSON file.
"""
function loadlog(filename::String)
    data = JSON3.read(read(filename, String))
    
    actions = [TreeverseAction(
        Symbol(action["action"]), 
        action["τ"], 
        action["δ"], 
        action["step"], 
        action["depth"]
    ) for action in data["actions"]]
    
    logger = TreeverseLog(actions, Ref(data["depth"]), Ref(data["peak_mem"]))
    return logger
end


function binomial_fit(N::Int, δ::Int)
    τ = 1
    while N > binomial(τ+δ, τ)
        τ += 1
    end
    return τ
end

function mid(δ, τ, σ, ϕ)
    κ = ceil(Int, (δ*σ + τ*ϕ)/(τ+δ))
    if κ >= ϕ && δ > 0
        κ = max(σ+1, ϕ-1)
    end
    return κ
end

"""
    treeverse(f, gf, s; δ, N, τ=binomial_fit(N,δ), f_inplace=true, logger = TreeverseLog())

Treeverse algorithm for back-propagating a program memory efficiently.

Positional arguments
* `f`, the step function that ``s_{i+1} = f(s_i)``,
* `gf`, the single step gradient function that ``g_i = gf(s_i, g_{i+1})``. When ``g_{i+1}`` is `nothing`, it should return the gradient passed from the later step.
* `s`, the initial state ``s_0``,

Keyword arguments
* `δ`, the number of checkpoints,
* `N`, the number of time steps,
* `τ`, the number of sweeps, it is chosen as the smallest integer that `binomial(τ+δ, τ) >= N` by default,
* `f_inplace = false`, whether `f` is inplace,
* `logger = TreeverseLog()`, the logger.

Ref: https://www.tandfonline.com/doi/abs/10.1080/10556789208805505
"""
function treeverse(f, gf, s::T; δ, N, τ=binomial_fit(N,δ), f_inplace=false, logger = TreeverseLog()) where T
    state = Dict(0=>s)
    if N > binomial(τ+δ, τ)
        error("please input a larger `τ` and `δ` so that `binomial(τ+δ, τ) >= N`!")
    end
    g = treeverse!(f, gf, state, nothing, δ, τ, 0, 0, N, logger, f_inplace)
    return g
end

function treeverse!(f, gf, state::Dict{Int,T}, g, δ, τ, β, σ, ϕ, logger, f_inplace) where T
    logger.depth[] += 1
    # cache sσ
    if σ > β
        δ -= 1
        s = state[β]
        for j=β:σ-1
            s = getf(f, j)(s)
            push!(logger, :call, τ, δ, j)
        end
        store_state!(state,σ, f_inplace ? copy(s) : s)
        s = nothing
        push!(logger, :store, τ, δ, σ)
        logger.peak_mem[] = max(logger.peak_mem[], length(state))
    elseif σ < β
        error("treeverse fails! σ < β")
    end

    κ = mid(δ, τ, σ, ϕ)
    while τ>0 && κ < ϕ
        g = treeverse!(f, gf, state, g, δ, τ, σ, κ, ϕ, logger, f_inplace)
        τ -= 1
        ϕ = κ
        κ = mid(δ, τ, σ, ϕ)
    end

    g = getf(gf, σ)(state[σ], g)
    push!(logger, :grad, τ, δ, σ)
    if σ>β
        # remove state[σ]
        delete_state!(state, σ)
        push!(logger, :fetch, τ, δ, σ)
    end
    return g
end

@inline function store_state!(state::Dict, i::Int, x)
    state[i] = x
end

@inline function delete_state!(state::Dict, i::Int)
    pop!(state, i)
end

getf(f, i::Int) = f
getf(f::AbstractArray, i::Int) = f[i]