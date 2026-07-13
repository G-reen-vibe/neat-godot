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

### Fix plan:
1. Add `_integrate_forces` teleport pattern to all physics envs (CartPole, Acrobot, Pong ball)
2. Rework live-env drive loop: drive from env's own `_physics_process`, cleanly separate training vs live viz
3. Fix Pong paddles (sync_to_physics=false or CharacterBody2D)
4. Fix Pong _max_steps in _make_extra
5. Add visual indicators: genome label, episode counter, training overlay, episode-end flash
6. Run full e2e test, handtrace, fix, re-test
7. Commit incrementally
