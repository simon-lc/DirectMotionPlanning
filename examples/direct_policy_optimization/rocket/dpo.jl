include(joinpath(pwd(), "src/direct_policy_optimization/dpo.jl"))
include(joinpath(@__DIR__, "rocket_nominal.jl"))
include(joinpath(@__DIR__, "rocket_slosh.jl"))

# DPO
N = 2 * model_sl.n
D = 2 * model_sl.d

β = 1.0
δ = 1.0e-3

# Initial samples
x1_sample = resample(x1_slosh, Diagonal(ones(model_sl.n)), 1.0e-3)

prob_nom = prob_nominal.prob

# Mean problem
prob_mean = trajectory_optimization(
				model_sl,
				EmptyObjective(),
				T,
				dynamics = false,
				ul = control_bounds(model, T,
					[Inf * ones(2); 0.0],
					[Inf * ones(2); 0.0])[1],
				uu = control_bounds(model, T,
					[Inf * ones(2); 0.0],
					[Inf * ones(2); 0.0])[2])

# Sample problems
prob_sample = [trajectory_optimization(
				model_sl,
				EmptyObjective(),
				T,
				xl = state_bounds(model_sl, T, x1 = x1_sample[i])[1],
				xu = state_bounds(model_sl, T, x1 = x1_sample[i])[2],
				ul = ul,
				uu = uu,
				dynamics = false,
				con = con_free_time
				) for i = 1:N]

# Sample objective
Q = [(t < T ? Diagonal(100.0 * ones(model_nom.n))
	: Diagonal(1000.0 * ones(model_nom.n))) for t = 1:T]
R = [Diagonal([1.0; 1.0; 100.0]) for t = 1:T-1]

obj_sample = sample_objective(Q, R)
policy = linear_feedback(6, 2,
	idx_input = collect([1, 2, 3, 5, 6, 7]),
	idx_input_nom = (1:6),
	idx_output = (1:2))
dist = disturbances([Diagonal(δ * ones(model_sl.n)) for t = 1:T-1])
sample = sample_params(β, T)

prob_dpo = dpo_problem(
	prob_nom, prob_mean, prob_sample,
	obj_sample,
	policy,
	dist,
	sample)

# TVLQR policy
x̄_nom, ū_nom = unpack(z̄_nom, prob_nominal)
K, P = tvlqr(model_nom, x̄_nom, ū_nom, 0.0, Q, R)

# Pack
z0 = zeros(prob_dpo.num_var)
z0[prob_dpo.prob.idx.nom] = copy(z̄_nom)
z0[prob_dpo.prob.idx.mean] = copy(z̄_slosh)
for i = 1:N
	z0[prob_dpo.prob.idx.sample[i]] = copy(z̄_slosh)
end
for t = 1:T-1
	z0[prob_dpo.prob.idx.policy[prob_dpo.prob.idx.θ[t]]] = vec(copy(K[t]))
end

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
