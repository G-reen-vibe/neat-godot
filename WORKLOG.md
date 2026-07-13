# Worklog: neat-godot env/visualization bug fixes

## Task: Fix all environment + live-visualization bugs

### Bugs identified (from analysis):
- RC1: RigidBody2D state set from outside `_integrate_forces()` — unreliable teleport
- RC2: Live env's `_physics_process` permanently disabled; `step_env()` driven from RunScreen only when paused
- RC3: Live env frozen during training with no visual feedback
- RC4: No episode-end / reset indication in UI
- RC5: `AnimatableBody2D.sync_to_physics=true` causes 1-frame collision lag (Pong)
- RC6: Pong `_max_steps` silently overridden to 500 (should be 1200)
- RC7: N/B during training resets a frozen env (no visible effect)
- U1-U5: Various UI/UX issues (no training feedback, no genome label, etc.)

### Fixes applied:

#### Commit 0d03de1: Fix RC1 — teleport pattern
- Created `TeleportBody2D` class (extends RigidBody2D) with `request_teleport()` + `_integrate_forces()` override
- CartPole: Cart + Pole now use TeleportBody2D; reset() queues teleports
- Acrobot: Link1 + Link2 now use TeleportBody2D; reset() queues teleports
- Pong: Ball now uses TeleportBody2D; reset() + ball-after-goal queues teleports
- Pong paddles: sync_to_physics=false (fixes RC5: 1-frame collision lag)

#### Commit 846118a: Fix RC2-RC7 — rework live-env drive loop
- NeatPhysicsEnvironment: added live_genome, live_mode, live_forward_mode, live_episode_count
- Added _live_step() helper: reset-if-done -> step_env -> apply_action
- All physics envs: _physics_process branches on live_mode
- RunScreen: replaced _drive_live_env with _set_live_env_active(bool)
- EnvViewport: added overlay info (training indicator, genome label, episode counter)
- config_screen: Pong _max_steps now 1200 (was defaulting to 500)

#### Commit b38b1b8: Add test_live_env_drive
- New test verifying live-env self-drive, auto-reset, genome switch, teleport reliability
- Key finding: teleports don't apply on frozen bodies (architecture handles this)

#### Commit 082e9d3: Fix episode counter bug
- Episode counter moved from RunScreen to env (live_episode_count)
- _live_step increments it when auto-resetting
- Explicitly disable _physics_process on live env after instantiation

#### Commit bf34b86: Yield physics frame after reset
- SceneEvaluator now yields one physics frame after reset() before the step loop
- This lets the teleport apply before the first action's impulse
- Fixed learning quality regression (CartPole was stuck at ~70, now reaches 500)

#### Commit 992d10e: Fix stale tests
- Removed evaluator.speedup references from test_pong_scene, test_acrobot_scene
- Updated test_pong_collision to use request_teleport for ball velocity

### Final test results:
- test_full_e2e_v2: ALL PASSED (XOR, CartPole, Acrobot, Pong, Save/Load)
- test_live_env_drive: ALL PASSED (CartPole, Acrobot, Pong live drive + teleport)
- test_cartpole_scene: PASSED (best=282, threshold=50)
- test_left_panel_overhaul: ALL PASSED (UI flow, N/B, WASD, status label)
- test_ui_smoke: ALL PASSED (all 4 envs)
- All backend unit tests: ALL PASSED (core, crossover, mutation, evaluation, population, similarity, speciation, random, init)

### All changes pushed to GitHub (6 commits, 3ea6abd..992d10e).
