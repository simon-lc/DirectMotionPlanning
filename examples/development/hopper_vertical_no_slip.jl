include(joinpath(pwd(), "models/hopper.jl"))
include(joinpath(pwd(), "src/objectives/velocity.jl"))
include(joinpath(pwd(), "src/constraints/contact_no_slip.jl"))
include(joinpath(pwd(), "src/constraints/free_time.jl"))
include(joinpath(pwd(), "src/constraints/loop.jl"))

# Free-time model
model_ft = free_time_model(no_slip_model(model))

function fd(model::Hopper, x⁺, x, u, w, h, t)
	q3 = view(x⁺, model.nq .+ (1:model.nq))
	q2⁺ = view(x⁺, 1:model.nq)
	q2⁻ = view(x, model.nq .+ (1:model.nq))
	q1 = view(x, 1:model.nq)
	u_ctrl = view(u, model.idx_u)
	λ = view(u, model.idx_λ)
	b = view(u, model.idx_b)
	h = u[end]

	[q2⁺ - q2⁻;
	((1.0 / h) * (M_func(model, q1) * (SVector{4}(q2⁺) - SVector{4}(q1))
	- M_func(model, q2⁺) * (SVector{4}(q3) - SVector{4}(q2⁺)))
	+ transpose(B_func(model, q3)) * SVector{2}(u_ctrl)
	+ transpose(N_func(model, q3)) * SVector{1}(λ)
	+ transpose(P_func(model, q3)) * SVector{2}(b)
	- h * G_func(model, q2⁺))]
end

model_ft.m
model_ft.idx_s
function no_slip(model::Hopper, x⁺, u, h)
	q3 = view(x⁺, model.nq .+ (1:model.nq))
	q2 = view(x⁺, 1:model.nq)
	λ = view(u, model.idx_λ)
	s = view(u, model.idx_s)
	h = u[end]
	return s[1] - (λ' * _P_func(model, q3) * (q3 - q2) / (1.0e-6 + h))[1]
end

# Horizon
T = 51

# Time step
tf = 1.0
h = tf / (T - 1)

# Bounds
_uu = Inf * ones(model_ft.m)
_uu[end] = 2.0 * h
_ul = zeros(model_ft.m)
_ul[model_ft.idx_u] .= -Inf
_ul[end] = 0.5 * h
ul, uu = control_bounds(model_ft, T, _ul, _uu)

# Initial and final states
z_h = 0.25
q1 = [0.0, 0.5 + z_h, 0.0, 0.25]

xl, xu = state_bounds(model_ft, T,
		[model_ft.qL; model_ft.qL],
		[model_ft.qU; model_ft.qU],
        x1 = [q1; Inf * ones(model.nq)])

# Objective
Qq = Diagonal([1.0, 1.0, 1.0, 1.0])
Q = cat(0.5 * Qq, 0.5 * Qq, dims = (1, 2))
QT = cat(0.5 * Qq, 1.0 * Diagonal(ones(model_ft.nq)), dims = (1, 2))
R = Diagonal([1.0e-1, 1.0e-1, zeros(model_ft.m - model_ft.nu)...])

obj_tracking = quadratic_time_tracking_objective(
    [Diagonal(zeros(model_ft.n)) for t = 1:T],
    [R for t = 1:T-1],
    [zeros(model_ft.n) for t = 1:T],
    [zeros(model_ft.m) for t = 1:T],
    1.0)
obj_contact_penalty = PenaltyObjective(1.0e5, model_ft.m - 1)
obj_velocity = velocity_objective(
    [Diagonal(1.0e-1 * ones(model_ft.nq)) for t = 1:T-1],
    model_ft.nq,
    h = h,
    idx_angle = collect([3]))
obj = MultiObjective([obj_tracking, obj_contact_penalty])#, obj_velocity])

# Constraints
con_free_time = free_time_constraints(T)
con_contact = contact_no_slip_constraints(model_ft, T)
con_loop = loop_constraints(model_ft, 1, T)

con = multiple_constraints([con_free_time, con_contact, con_loop])

# Problem
prob = trajectory_optimization_problem(model_ft,
               obj,
               T,
               xl = xl,
               xu = xu,
               ul = ul,
               uu = uu,
               con = con
               )

# Trajectory initialization
x0 = [[q1; q1] for t = 1:T] # linear interpolation on state
u0 = [[1.0e-5 * rand(model_ft.m-1); h] for t = 1:T-1] # random controls

# Pack trajectories into vector
z0 = pack(x0, u0, prob)

#NOTE: may need to run examples multiple times to get good trajectories
# Solve nominal problem
include_snopt()
@time z̄ = solve(prob, copy(z0),
	nlp = :SNOPT7,
	tol = 1.0e-3, c_tol = 1.0e-3, mapl = 5,
	time_limit = 60)

check_slack(z̄, prob)
x̄, ū = unpack(z̄, prob)
tf, t, hc = get_time(ū)

include(joinpath(pwd(), "models/visualize.jl"))
vis = Visualizer()
render(vis)
visualize!(vis, model_ft, state_to_configuration(x̄), Δt = ū[1][end])

@save joinpath(@__DIR__, "hopper_vertical_gait_no_slip.jld2") x̄ ū
