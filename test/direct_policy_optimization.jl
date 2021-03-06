"""
    test direct policy optimization
"""
prob_dpo = prob_dpo.prob
# objective
z0 = rand(prob_dpo.num_var)
tmp_o(z) = eval_objective(prob_dpo,z)
∇j = zeros(prob_dpo.num_var)
eval_objective_gradient!(∇j, z0, prob_dpo)
@assert norm(ForwardDiff.gradient(tmp_o, z0) - ∇j) < 1.0e-10

# sample dynamics
con_dynamics = sample_dynamics_constraints(prob_dpo.prob,
    prob_dpo.N, prob_dpo.N + prob_dpo.D)
c0 = zeros(con_dynamics.n)
_c(c,z) = constraints!(c, z, con_dynamics,
    prob_dpo.prob, prob_dpo.idx, prob_dpo.N, prob_dpo.D,
    prob_dpo.dist, prob_dpo.sample)
∇c_fd = zeros(con_dynamics.n, prob_dpo.num_var)
FiniteDiff.finite_difference_jacobian!(∇c_fd, _c, z0)
# ∇c_fd = ForwardDiff.jacobian(_c, c0, z0)
spar = constraints_sparsity(con_dynamics, prob_dpo.prob, prob_dpo.idx,
    prob_dpo.N, prob_dpo.D)
∇c_vec = zeros(length(spar))
∇c = zeros(con_dynamics.n, prob_dpo.num_var)
constraints_jacobian!(∇c_vec, z0, con_dynamics,
    prob_dpo.prob, prob_dpo.idx, prob_dpo.N, prob_dpo.D,
    prob_dpo.dist, prob_dpo.sample)
for (i,k) in enumerate(spar)
    ∇c[k[1],k[2]] = ∇c_vec[i]
end
@assert norm(vec(∇c) - vec(∇c_fd)) < 1.0e-5
@assert sum(∇c) - sum(∇c_fd) < 1.0e-5

prob_dpo.con[2]
# policy
prob_dpo.con[2]
model.m * (T - 1) * (N + 1)
con_policy = prob_dpo.con[2]
c0 = zeros(con_policy.n)
_c(c,z) = constraints!(c, z, con_policy, prob_dpo.policy,
    prob_dpo.prob, prob_dpo.idx, prob_dpo.N)
_c(c0,z0)
# ∇c_fd = zeros(con_policy.n, prob_dpo.num_var)
# FiniteDiff.finite_difference_jacobian!(∇c_fd, _c, z0)
∇c_fd = ForwardDiff.jacobian(_c, c0, z0)
spar = constraints_sparsity(con_policy, prob_dpo.policy, prob_dpo.prob,
    prob_dpo.idx, prob_dpo.N)
∇c_vec = zeros(length(spar))
∇c = zeros(con_policy.n, prob_dpo.num_var)
constraints_jacobian!(∇c_vec, z0, con_policy, prob_dpo.policy,
    prob_dpo.prob, prob_dpo.idx, prob_dpo.N)

for (i,k) in enumerate(spar)
    ∇c[k[1],k[2]] = ∇c_vec[i]
end
@assert norm(vec(∇c) - vec(∇c_fd)) < 1.0e-10
@assert sum(∇c) - sum(∇c_fd) < 1.0e-10

# constraints
c0 = zeros(prob_dpo.num_con)
_c(c,z) = eval_constraint!(c, z, prob_dpo)

∇c_fd = zeros(prob_dpo.num_con, prob_dpo.num_var)
FiniteDiff.finite_difference_jacobian!(∇c_fd, _c, z0)
spar = sparsity_jacobian(prob_dpo)
∇c_vec = zeros(length(spar))
∇c = zero(∇c_fd)
eval_constraint_jacobian!(∇c_vec, z0, prob_dpo)
for (i,k) in enumerate(spar)
    ∇c[k[1],k[2]] = ∇c_vec[i]
end
@assert norm(vec(∇c) - vec(∇c_fd)) < 1.0e-5
@assert sum(∇c) - sum(∇c_fd) < 1.0e-5


# sample dynamics
model = model_slosh
t = 3
xt = view(z0_dpo, prob_dpo.idx.xt[t])
ut = view(z0_dpo, prob_dpo.idx.ut[t])
μ = view(z0_dpo, prob_dpo.idx.mean[prob_dpo.prob.mean.idx.x[t]])
ν = view(z0_dpo, prob_dpo.idx.mean[prob_dpo.prob.mean.idx.u[t]])

propagate_dynamics(model, rand(model.n), rand(model.m), rand(model.d), 0.0, t)
propagate_dynamics_jacobian(model, rand(model.n), rand(model.m), rand(model.d), 0.0, t)

propagate_dynamics(model, μ, ν, ones(model.d), 0.0, t)
propagate_dynamics_jacobian(model, μ, ν, 0.1 * ones(model.d), 0.0, t)

sample_dynamics(model, xt, ut, μ, ν, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)

a1, a2, a3, a4 = sample_dynamics_jacobian(model, xt, ut, μ, ν, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)

sdx(y) = sample_dynamics(model, y, ut, μ, ν, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)[1]
sdx(xt)

sdu(y) = sample_dynamics(model, xt, y, μ, ν, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)[1]
sdu(ut)

sdμ(y) = sample_dynamics(model, xt, ut, y, ν, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)[1]
sdμ(μ)

sdν(y) = sample_dynamics(model, xt, ut, μ, y, prob_dpo.dist.w, 0.0, t,
	prob_dpo.sample.β)[1]
sdν(ν)

@assert norm(FiniteDiff.finite_difference_jacobian(sdx, xt) - a1, Inf) < 1.0e-3
@assert norm(FiniteDiff.finite_difference_jacobian(sdu, ut) - a2, Inf) < 1.0e-4
@assert norm(FiniteDiff.finite_difference_jacobian(sdμ, μ) - a3, Inf) < 1.0e-4
@assert norm(FiniteDiff.finite_difference_jacobian(sdν, ν) - a4, Inf) < 1.0e-3
