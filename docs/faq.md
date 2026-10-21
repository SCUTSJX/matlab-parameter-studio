<div align="center">

**English** · [简体中文](faq.zh-CN.md)

# FAQ

</div>

> [User guide](guide.md) · [Examples](../examples/README.md) · [Project README](../README.md)

### Which MATLAB release do I need?

MATLAB **R2023b or newer**. Development and testing are currently on R2025a. The app uses multi-select tables and cancelable progress dialogs that require R2023b-era UI features.

### Does it modify my original script?

No. Edits are applied to a temporary copy and, when you choose **Save tuned .m**, to a separate `<name>_tuned.m`. The original `.m` file is never written by a normal run or save.

### Can it open `.mlx` Live Scripts or `.slx` Simulink models?

No. It only supports `.m` text scripts. Simulink block parameters and Live Scripts are out of scope for 1.0.

### Why are some numbers missing from the recommended list?

Detection is heuristic. Plot styling, array sizes, indexes and low-confidence literals are deliberately scored low. Use **All numbers** to see everything, `% @param` to force a literal into the recommended list, and `% @ignore` to suppress a false positive.

### Why is my parameter named differently from the variable?

The scanner infers names from assignments, struct fields, arrays and ranges. For complex expressions it may use a positional name or a nearby comment. Renaming the variable or adding `% @param name` makes the intent explicit.

### Can I run a function file directly?

Not directly. Function files can be scanned and saved, but you need to open a script that calls the function. If the function is a configuration function, open it, click **Entry...**, choose the project entry script, and run that.

### Do I need Parallel Computing Toolbox?

No. The app works without it. PCT enables background runs and parallel sweeps. Without PCT those options are disabled or run serially.

### Why did several MATLAB processes appear?

A local `parpool('Processes')` starts one worker per physical core plus the MATLAB client. Use `app.NumWorkers` (or `app.MaxWorkers`) to limit workers, and `app.KeepParallelPool = false` to close the pool after the run. To close an existing pool immediately:

```matlab
delete(gcp('nocreate'))
```

### Are sweep results reproducible?

Yes for a fixed `app.SweepSeed`. Scenario *k* uses `SweepSeed + k - 1`; serial and parallel paths seed the same scenario identically. If the script calls `rng` internally, its call takes precedence.

### Where are runs, sessions, presets and annotations stored?

Next to the source script:

- `parameter_studio_runs/` — run outputs
- `<name>_session.json` — unsaved table state
- `<name>_presets.json` — named parameter presets
- `<name>_manual.json` — manually added parameters
- `<name>_annotations.json` — AI/human annotations

Run outputs and local state are ignored by Git by default.

### Why don't I see `_tuned.m` or `_params.json` in `git status`?

They are generated artifacts and are ignored by `.gitignore`. If you want to version a particular tuned script or parameter export, force-add it:

```bash
git add -f demo/demo_simulation_tuned.m
git add -f demo/demo_simulation_tuned_params.json
```

### Can I share an HTML report?

Yes. The report uses relative links to its `figures/` folder, so share the whole run folder, not only `report.html`.

### Does the app upload my code or results?

No. There is no network access or telemetry. Reports and results stay on disk. Running a script still executes its MATLAB code, so only run scripts you trust.

### How do I switch between Chinese and English?

```matlab
MatlabParameterStudioEnglish
% or
MatlabParameterStudio('Language', 'en')
% back to Chinese
mps.setLanguage('zh')
```

### How do I compare two runs?

Open **Run history**, select one run and click **Set as A**, select another and click **Set as B**, then click **Compare A / B**. The result is written to `compare.html` and `compare.json` in the B run folder.

### How do I clean old results?

Open **Run history** and use **Clean old runs...**. You can keep the latest 10 or 30 runs; the current run is protected.

### How do I add a parameter the scanner missed?

Click **Add parameter...**, give it a valid MATLAB variable name and a numeric value. It is stored in `<name>_manual.json` and prepended as an assignment when the run script is generated. Project mode does not support manual parameters.

### Why does the report show fewer variables than my workspace?

Workspace capture has per-variable and total memory budgets (`MaxVariableMB`, `MaxTotalMB`). Very large variables are skipped and logged. Lazy loading above `LazyWorkspaceMB` writes the workspace to `workspace.mat` and keeps only a summary in memory.

### How do I verify the installation?

```matlab
addpath('tests')
run_tests
```

For a complete environment check plus tests and a timestamped log:

```matlab
mps.preflight()
```

### Something else is wrong

Include the MATLAB release, the command you ran, the source script (or a minimal reproduction), the error text and the relevant log file when opening an issue. The preflight log under `logs/` is useful, but review it for local paths before sharing.
