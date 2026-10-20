# Tests

The test suite is split into scripts that run in the `run_tests` workspace, so
they can share the demo fixture and temporary paths without a test framework.

## Run locally

```matlab
addpath('tests')
run_tests
```

Or from a terminal:

```bat
matlab -batch "addpath('tests'); run_tests"
```

A successful run prints `ALL TESTS PASSED`.

## Files

| File | Covers |
| --- | --- |
| `test_detection.m` | detection, validation, annotations, manual params, locks |
| `test_execution.m` | run/report, workspace limits, lazy workspace, compare, presets |
| `test_scanning.m` | error path mapping and function-file scanning |
| `test_sweep.m` | sweep parsing, dialog, report, metrics CSV |
| `test_bulk.m` | bulk edit and paste |
| `test_history.m` | run history and duplicate-name compare |
| `test_session.m` | undo/redo, session restore, diff and source stamps |
| `test_executors.m` | `RunExecutor` |
| `test_project.m` | multi-file project execution and project sweep |
| `test_parallel.m` | parallel sweep, background run, cancel (PCT if licensed) |
| `test_app.m` | App construction and public UI actions |
| `test_cleanup.m` | shadow file deletion sync and stale shadow cleanup |

`run_tests.m` only sets up the fixture, calls these scripts, and cleans up
figures and a test-created parallel pool.

## Parallel Computing Toolbox

When PCT is not licensed, the parallel section is skipped. When it is
licensed, the suite creates a small adaptive pool (normally 2 workers for the
2-scenario test) and stops it before `test_app` finishes. A pool that already
existed before the test run is left alone.

## Preflight and logs

Before a release, or when a machine behaves differently, run:

```matlab
mps.preflight
```

This checks the local MATLAB version, writable temp directory, demo script and
required UI functions, then runs the full suite. It writes a timestamped log to
`logs/preflight_*.log` (gitignored).

```matlab
mps.preflight('Full', false)   % environment check only
mps.checkEnvironment           % read-only environment report
```

Everything is local. There is no self-hosted runner, no GitHub-specific
execution and no network access.

## Adding tests

1. Add a `test_<area>.m` script with plain assertions.
2. Use `tempdir` for generated files and remove them before the script ends.
3. Call the script from `run_tests.m` in dependency order.
4. Do not start a permanent parallel pool; stop a pool you created.

Warnings on user-visible file or report paths should go through
`mps.logWarning`, not an empty `catch`.
