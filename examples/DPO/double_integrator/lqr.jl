include(joinpath(pwd(), "src/direct_policy_optimization/dpo.jl"))
include(joinpath(pwd(), "src/models/double_integrator.jl"))

# horizon
T = 51

# Bounds

# ul <= u <= uu
ul, uu = control_bounds(model, T, 0.0, 0.0)

# Initial and final states
x0 = zeros(model.n)
xl, xu = state_bounds(model, T, x0, x0)

# Problem
prob_nom = trajectory_optimization(
			model,
			EmptyObjective(),
			T,
			xl = xl,
			xu = xu,
			ul = ul,
			uu = uu,
			)

# DPO
N = 2 * model.n
D = 2 * model.d

α = 1.0
β = 1.0 / (N + D)
γ = 0.5
δ = 1.0

x1 = resample(zeros(model.n), Diagonal(ones(model.n)), 1.0)

# mean problem
prob_mean = trajectory_optimization(
				model,
				EmptyObjective(),
				dynamics = false,
				T)

# sample problems
prob_sample = [trajectory_optimization(
				model,
				EmptyObjective(),
				dynamics = false,
				T,
				xl = state_bounds(model, T, x1 = x1[i])[1],
				xu = state_bounds(model, T, x1 = x1[i])[2]
				) for i = 1:N]

# sample objective
Q = [Diagonal(ones(model.n)) for t = 1:T]
R = [Diagonal(ones(model.m)) for t = 1:T-1]

obj_sample = sample_objective(Q, R)
policy = linear_feedback(model.n, model.m)
dist = disturbances([Diagonal(δ * ones(model.d)) for t = 1:T-1])
sample = sample_params(α, β, γ, T)

prob_dpo = dpo_problem(
	prob_nom, prob_mean, prob_sample,
	obj_sample,
	policy,
	dist,
	sample)

z0 = ones(prob_dpo.num_var)

# Solve
z_sol = solve(prob_dpo, copy(z0),
	tol = 1.0e-8, c_tol = 1.0e-8,
	mapl = 0)

# tvlqr policy
A, B = get_dynamics(model)
K = tvlqr(
	[A for t = 1:T-1],
	[B for t = 1:T-1],
	[Q[t] for t = 1:T],
	[R[t] for t = 1:T-1])

θ = [reshape(z_sol[prob_dpo.prob.idx.policy[prob_dpo.prob.idx.θ[t]]],
	model.m, model.n) for t = 1:T-1]

policy_error = [norm(vec(θ[t] - K[t])) / norm(vec(K[t])) for t = 1:T-1]
println("policy difference (inf. norm): $(norm(policy_error, Inf))")