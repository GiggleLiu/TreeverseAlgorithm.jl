using TreeverseAlgorithm, Test, ForwardDiff
using NiLang
using NiLang.AD: GVar

@testset "dumplog" begin
    logger = TreeverseLog(TreeverseAlgorithm.TreeverseAction[], Ref(0), Ref(0))
    push!(logger, :call, 1, 1, 1)
    push!(logger, :grad, 1, 1, 1)
    push!(logger, :store, 1, 1, 1)
    push!(logger, :fetch, 1, 1, 1)
    push!(logger, :call, 1, 1, 1)
    push!(logger, :grad, 1, 1, 1)
    dumplog(logger, "test.json")
    logger2 = loadlog("test.json")
    @test logger.actions == logger2.actions
    @test logger.depth[] == logger2.depth[]
    @test logger.peak_mem[] == logger2.peak_mem[]
end

@testset "treeverse" begin
    struct P3{T}
        x::T
        y::T
        z::T
    end

    Base.zero(::Type{P3{T}}) where T = P3(zero(T), zero(T), zero(T))
    Base.zero(::P3{T}) where T = P3(zero(T), zero(T), zero(T))


    @inline function Base.:(+)(a::P3, b::P3)
        P3(a.x + b.x, a.y + b.y, a.z + b.z)
    end

    @inline function Base.:(/)(a::P3, b::Real)
        P3(a.x/b, a.y/b, a.z/b)
    end

    @inline function Base.:(*)(a::Real, b::P3)
        P3(a*b.x, a*b.y, a*b.z)
    end


    function lorentz(t, y, θ)
        P3(10*(y.y-y.x), y.x*(27-y.z)-y.y, y.x*y.y-8/3*y.z)
    end

    function rk4_step(f, t, y, θ; Δt)
        k1 = Δt * f(t, y, θ)
        k2 = Δt * f(t+Δt/2, y + k1 / 2, θ)
        k3 = Δt * f(t+Δt/2, y + k2 / 2, θ)
        k4 = Δt * f(t+Δt, y + k3, θ)
        return y + k1/6 + k2/3 + k3/3 + k4/6
    end

    function rk4(f, y0::T, θ; t0, Δt, Nt) where T
        history = zeros(T, Nt+1)
        history[1] = y0
        y = y0
        for i=1:Nt
            y = rk4_step(f, t0+(i-1)*Δt, y, θ; Δt=Δt)
            @inbounds history[i+1] = y
        end
        return history
    end


    @i @inline function :(+=)(identity)(Y::P3, X::P3)
        Y.x += X.x
        Y.y += X.y
        Y.z += X.z
    end

    @i @inline function :(+=)(*)(Y::P3, a::Real, X::P3)
        Y.x += a * X.x
        Y.y += a * X.y
        Y.z += a * X.z
    end

    @i @inline function :(+=)(/)(Y::P3, X::P3, b::Real)
        Y.x += X.x/b
        Y.y += X.y/b
        Y.z += X.z/b
    end

    @i function lorentz!(y!::P3{T}, t, y::P3{T}, θ) where T
        @routine @invcheckoff begin
            @zeros T a b c b_a ab αc ac
            a += y.x
            b += y.y
            c += y.z
            b_a += b-a
            ab += a * b
            αc += (8/3) * c
            c -= 27
            ac += a * c
        end
        y!.x += 10 * b_a
        y!.y -= ac + b
        y!.z += ab - αc
        ~@routine
    end

    @i function rk4_step!(f, y!::T, y::T, θ; Δt, t) where T
        @routine @invcheckoff begin
            @zeros T k1 k2 k3 k4 o1 o2 o3 o4 yk1 yk2 yk3
            f(o1, t, y, θ)
            k1 += Δt * o1
            yk1 += y
            yk1 += k1 / 2
            t += Δt/2
            f(o2, t, yk1, θ)
            k2 += Δt * o2
            yk2 += y
            yk2 += k2 / 2
            f(o3, t, yk2, θ)
            k3 += Δt * o3
            yk3 += y
            yk3 += k3
            t += Δt/2
            f(o4, t, yk3, θ)
            k4 += Δt * o4
        end
        y! += y
        y! += k1 / 6
        y! += k2 / 3
        y! += k3 / 3
        y! += k4 / 6
        ~@routine
    end

    @i function rk4!(f, history, y0::T, θ; t0, Δt, Nt) where T
        history[1] += y0
        @invcheckoff @inbounds for i=1:Nt
            rk4_step!(f, history[i+1], history[i], θ; Δt=Δt, t=t0+(i-1)*Δt)
        end
    end

    @i function iloss!(out, f, history, y0, θ; t0, Δt, Nt)
        rk4!((@const f), history, y0, θ; t0=t0, Δt=Δt, Nt=Nt)
        out += history[end].x
    end
    @i function i_step_fun(state2, state)
        rk4_step!((@const lorentz!), state2.:2, state.:2, (); Δt=3e-3, t=state[1])
        state2.:1 += state.:1 + 3e-3
    end

    function step_fun(x)
        i_step_fun((0.0, zero(x[2])), x)[1]
    end

    function backward(x, g)
        if g===nothing
            g = (0.0, P3(1.0, 0.0, 0.0))
        end
        y = step_fun(x)
        _, gs = (~i_step_fun)(
            (GVar(y[1], g[1]), P3(GVar(y[2].x, g[2].x), GVar(y[2].y, g[2].y), GVar(y[2].z,g[2].z))),
            (GVar(x[1]), GVar(x[2])))
        NiLang.AD.grad(gs[1]), NiLang.AD.grad(gs[2])
    end

    @testset "treeverse gradient" begin
        x0 = P3(1.0, 0.0, 0.0)
        for N in [20, 120, 126]
            g_fd = ForwardDiff.gradient(x->rk4(lorentz, P3(x...), nothing; t0=0.0, Δt=3e-3, Nt=N)[end].x, [x0.x, x0.y, x0.z])
            g_tv = treeverse(step_fun, backward, (0.0, x0); δ=4, N=N)
            @test g_fd ≈ [g_tv[2].x, g_tv[2].y, g_tv[2].z]
        end
    end
end