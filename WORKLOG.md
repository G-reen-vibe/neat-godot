# Worklog: neat-godot env replacement with godot_rl

## Task: Replace broken envs with godot_rl envs via NeatRLAdapter

### Problem
The existing envs (XOR, CartPole, Acrobot, Pong) had broken scene configs and
dysfunctional physics. The godot_rl repo has tested, working envs that use a
different interface (RLEnvironment/RLAgent with PackedFloat32Array).

### Solution
Created a NeatRLAdapter base class that bridges RLEnvironment to
NeatPhysicsEnvironment. The adapter:
- Instantiates an RL env scene as a child
- Converts Dictionary<int,float> <-> PackedFloat32Array for state/action
- Drives the RL env's physics_step from step_env
- Accumulates per-step reward into cumulative fitness
- Handles multi-agent envs (Pong: primary + stationary secondary)

### Commits

#### Import godot_rl module
- Copied rl/ folder (core + envs + preview) from godot_rl into neat-godot
- All RL envs (cartpole, pong, lunar_lander, bipedal_walker) intact

#### Remove broken envs
- Deleted environments/{xor,cartpole,acrobot,pong}/
- Deleted env-specific tests (test_cartpole_scene, test_pong_scene, etc.)
- Deleted xor_truth_table UI component
- Created MockTestEnv for backend unit tests (replaces XorEnvironment)

#### Create NeatRLAdapter + per-env subclasses
- environments/neat_rl_adapter.gd: base adapter
- environments/cartpole/neat_cartpole_env.gd + .tscn
- environments/pong/neat_pong_env.gd + .tscn (with hit-detection fitness shaping)
- environments/lunar_lander/neat_lunar_lander_env.gd + .tscn
- environments/bipedal_walker/neat_bipedal_walker_env.gd + .tscn

#### Update UI
- env_select_screen: new 4-env list
- config_screen: per-env num_inputs/num_outputs/population_size/max_steps
- run_screen: loads adapter scenes, sets up IO via env_setup_fn
- env_viewport: new _draw methods for all 4 env types (pixel coords)

#### Bug fixes during testing
1. Reward accumulation: changed from delta to raw per-step reward
   (godot_rl agents return per-step rewards, not running totals)
2. _reset_pending flag: skip first step_env after reset (teleport timing)
3. _step_skipped flag: lets subclasses skip their work when base skips
4. Stop step_env after is_done (prevents reward inflation from stale _reward)
5. Pong hit cooldown (10 steps) to prevent collision-jitter double-counting
6. Hide RL env visuals (Camera2D + Polygon2D) in live visualization
7. Fix cartpole pole direction (was drawn upside down)

### Test results
- test_adapter_cartpole: PASSED (fitness=61 after 62 steps)
- test_adapter_pong: PASSED (fitness=7.54, 155 steps, hit detection works)
- test_adapter_lunar_lander: PASSED (fitness=-5.04, OOB with full thrust)
- test_adapter_bipedal_walker: PASSED (fitness=43.75, 404 steps alive)
- test_train_cartpole: PASSED (best=200, avg=145 over 5 gens)
- test_train_all_envs: PASSED (all 4 envs, 3 gens each)
- test_full_gameplay: PASSED (training + live viz + cleanup on all 4 envs)
- All backend unit tests: PASSED

### Changes pushed to GitHub (branch: replace-envs-with-godot-rl)
