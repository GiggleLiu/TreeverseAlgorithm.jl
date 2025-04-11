using .Viznet
using .Viznet.Compose

export treeverse_pebblegame

@info "TreeverseAlgorithm: You just imported `Viznet`, you can use
    * (image, nstep) = treeverse_pebblegame(N, δ)
"

"""
    (image, nstep) = treeverse_pebblegame(N, δ)

Returns a tuple of Context object (check Compose.jl) and the number of steps.
Show to pebble game solution for treeverse algorithm, `N` is the total number of steps, `δ` is the number of checkpoints.
"""
function treeverse_pebblegame(N::Int, δ; scale=1.0)
    x0 = 0.0
    logger = TreeverseLog()
    g_tv = treeverse(x->0.0, (x,z)->0.0, 0.0; N=N, δ=δ,logger=logger)
    println("Treeverse peak memory = ", logger.peak_mem[])
    X = 1cm*(N+1)

    actions = copy(logger.actions)
    NY = count(a->a.action == :call, actions)+1
    Y = 1cm*NY
    Compose.set_default_graphic_size(X*scale, Y*scale)

    img = canvas() do
        checkpoints = []
        y = 0.5/(N+1)
        dy = 1/(N+1)
        ngrad = 1
        fstep = 0
        removed = []
        for (i, act) in enumerate(actions)
            pebbles = checkpoints
            new = []
            if act.action == :call
                pebbles = [pebbles..., act.step+1]
                push!(removed, act.step)
                new = [act.step+1]
                fstep = act.step
            elseif act.action == :store
                push!(checkpoints, act.step)
                continue
            elseif act.action == :fetch
                pebbles = [pebbles..., act.step]
                deleteat!(checkpoints, findfirst(==(act.step), checkpoints))
                push!(removed, act.step)
                continue
            elseif act.action == :grad
                ngrad += 1
                push!(removed, act.step)
                i==length(actions) || continue
            else
                error("")
            end
            showtape(N, pebbles; y=y, removed=removed, new=new, ngrad=ngrad, flag=false, label="")
            empty!(removed)
            y += dy
        end
    end
    img = Compose.compose(context(0, 0, 1.0, (N+1)/NY), img)
    return img, NY
end

function showtape(n::Int, checkpoints; removed=Int[], new=Int[], y=0.5, ngrad=0, flag=true, label="")
    unit = 1/(n+1)
    BG = "#AAAAAA"
    NEW = "#000000"
    EXIST = "#555555"
    r = 0.25
    a = 0.4
    grid = nodestyle(:square, fill(BG), stroke("transparent"), r=a*unit)
    grid_red = nodestyle(:square, fill("red"), stroke("transparent"), r=a*unit)
    pebble = nodestyle(:circle, fill(EXIST); r=r*unit)
    pebble_removed = nodestyle(:circle, fill("transparent"), stroke("black"), linewidth(10mm*unit); r=r*unit)
    pebble_new = nodestyle(:circle, fill(NEW); r=r*unit)
    tb_flag = textstyle(:default, fontsize(2))
    tb = textstyle(:default, fontsize(14pt), fill("white"))
    pebble >> (0.5*unit, y)
    flag && tb_flag >> (((n+0.5)*unit, y), "🚩")
    if !isempty(label)
        tb >> ((1.0, y), label)
    end
    for p in setdiff(removed, checkpoints)
        pebble_removed >> ((p+0.5)*unit, y)
    end
    for p in new
        pebble_new >> ((p+0.5)*unit, y)
    end
    for p in setdiff(checkpoints, new)
        pebble >> ((p+0.5)*unit, y)
    end
    for i = 0:n-ngrad
        grid >> ((i+0.5)*unit, y)
    end
    for i = n-ngrad+1:n
        grid_red >> ((i+0.5)*unit, y)
    end
end

