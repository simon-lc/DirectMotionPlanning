include(joinpath(pwd(), "src/direct_policy_optimization/dpo.jl"))
include(joinpath(@__DIR__, "quadrotor_broken_propeller.jl"))

# Nominal solution
x̄, ū = unpack(z̄, prob)
prob_nom = prob.prob

# DPO
N = 2 * model.n
D = 2 * model.d

β = 1.0
δ = 1.0e-3

# Initial samples
x1_sample = resample(x1, Diagonal(ones(model.n)), 1.0e-3)

# Mean problem
prob_mean = trajectory_optimization(
				model,
				EmptyObjective(),
				T,
				ul = control_bounds(model, T,
					[Inf * ones(4); 0.0],
					[Inf * ones(4); 0.0])[1],
				uu = control_bounds(model, T,
					[Inf * ones(4); 0.0],
					[Inf * ones(4); 0.0])[2],
				dynamics = false)

# Sample problems
uu_sample = []
for i = 1:6
	push!(uu_sample, copy(uu1))
end
for i = 1:6
	push!(uu_sample, copy(uu2))
end
for i = 1:6
	push!(uu_sample, copy(uu3))
end
for i = 1:6
	push!(uu_sample, copy(uu4))
end

prob_sample = [trajectory_optimization(
				model,
				EmptyObjective(),
				T,
				xl = state_bounds(model, T, x1 = x1_sample[i])[1],
				xu = state_bounds(model, T, x1 = x1_sample[i])[2],
				ul = ul,
				uu = control_bounds(model, T, Inf * ones(model.m), uu_sample[i])[2],
				dynamics = false,
				con = con_free_time) for i = 1:N]

# Sample objective
Q = [(t < T ? Diagonal(10.0 * ones(model.n))
	: Diagonal(100.0 * ones(model.n))) for t = 1:T]
R = [Diagonal(ones(model.m)) for t = 1:T-1]

obj_sample = sample_objective(Q, R)
policy = linear_feedback(model.n, model.m - 1)
dist = disturbances([Diagonal(δ * ones(model.n)) for t = 1:T-1])
sample = sample_params(β, T)

prob_dpo = dpo_problem(
	prob_nom, prob_mean, prob_sample,
	obj_sample,
	policy,
	dist,
	sample)

# TVLQR policy
K, P = tvlqr(model, x̄, ū, Q, R, 0.0)

# Pack
z0 = pack(z̄, K, prob_dpo)

# Solve
optimize = true

if optimize
	include_snopt()
	z = solve(prob_dpo, copy(z0),
		nlp = :SNOPT7,
		tol = 1.0e-2, c_tol = 1.0e-2,
		time_limit = 60 * 60)
	@save joinpath(@__DIR__, "sol_dpo.jld2") z
else
	println("Loading solution...")
	@load joinpath(@__DIR__, "sol_dpo.jld2") z
end
