# Release checklist

## Automated

```bat
matlab -batch "addpath('tests'); run_tests"
```

- all tests pass;
- no `MATLAB` / `MATLABWindow` processes remain afterwards;
- a test-created parallel pool is stopped;
- CI workflow `MATLAB tests` is green (or the same command has been run on
  the self-hosted runner).

## Manual smoke test

1. Open `demo/demo_simulation.m`, run, and open the HTML report.
2. Change `k`/`c`, save a preset, rerun, and reload the preset.
3. Open a multi-file project, run once, then run again (shadow reuse).
4. Delete or rename a project `.m` file and run again; no stale copy should
   remain in the shadow directory.
5. Run a small sweep and a project sweep; close figures and check the output
   folder.
6. Close the app and verify no MATLAB worker processes remain.

## Documentation

- `docs/screenshot.png` and `docs/screenshot_annotations.png` were generated
  with `docs/make_screenshots.m`;
- screenshots contain no user home directory or real project path;
- README usage and test commands match the release;
- `+mps/version.m` is bumped.

## Data safety

- original project `.m` files were not modified;
- result folders are under `parameter_studio_runs/`;
- stale shadow folders older than seven days are removed at app startup.
