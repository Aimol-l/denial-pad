# Mistake Notebook

This is the Mistake Notebook, use the mistake-notebook skill to retrive more details.

Below is a list of mistakes I previously made and solved:

## Mistake - Nested `with_states` deadlocks the compositor

- Creation Date: 2026-11-14
- Last Update Date: 2026-11-14
- Project: /home/aimol/Documents/Workspace/denial-pad
- Branch: main
- Commit: ac7ec97

### Problem:

- Reading an application's committed window geometry / asking for a size at an app scale above 1 froze deniald: `grim` never returned a frame, `denialctl status` timed out, and the tablet had to be rebooted.
- It started the moment a window opened with `apps.scale = 1.5` (Firefox), and only after adding "remember the sizes asked of a client".

### Insights:

- Smithay's `with_states(surface, ..)` / `states.cached_state.get::<SurfaceCachedState>()` take that surface's lock. A commit handler and a configure path already hold it, so a call made from there takes it again and waits on itself.
- Storing per-window bookkeeping in `states.data_map` is only safe when every reader runs outside the surface's lock; ours did not.
- Symptom shape: the compositor stops answering the control socket while doing work on a *newly opened, scaled* window — no panic, no log.

### Solution:

Keep per-window bookkeeping beside the surfaces, not in their state.

- Replace `states.data_map` storage with `OnceLock<Mutex<HashMap<ObjectId, VecDeque<..>>>>` keyed by the root surface id (application_scale.rs).
- Drop an entry when the surface leaves (`forget_surface` from `remove_surface_state`).
- When a value is needed inside a commit/configure path, take only that side table's lock, never the surface's state.
