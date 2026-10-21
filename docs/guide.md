<div align="center">

**English** · [简体中文](guide.zh-CN.md)

# User Guide

</div>

> [Project README](../README.md) · [Examples](../examples/README.md) · [FAQ](faq.md)

This guide covers the complete workflow: installing MATLAB Parameter Studio, scanning a script, editing and running parameters, reading reports, sweeping parameters, using project mode, and automating it from MATLAB.

## 1. Install and launch

**Requirements:** MATLAB R2023b or newer. Development and testing are on R2025a. Parallel Computing Toolbox is optional and enables background runs and parallel sweeps.

```matlab
cd('path/to/matlab-parameter-studio')
install                 % current MATLAB session
% install('Save')       % persist on the MATLAB path
```

Launch the UI:

```matlab
MatlabParameterStudio            % Chinese UI (default)
MatlabParameterStudioEnglish     % English UI
MatlabParameterStudio('Language','en')
```

For automation, hide the window:

```matlab
app = MatlabParameterStudio('Visible', 'off', 'Language', 'en');
```

## 2. First run

1. Click **Open .m file** and choose a script, for example `demo/demo_simulation.m`.
2. Review the parameter table. Edit the **New value** column; use the checkbox in **Use** to include a parameter in the run.
3. Click **Run**.
4. Open the generated HTML report, or click **Save tuned .m** to write a standalone script.

Results are written next to the source script:

```text
parameter_studio_runs/<timestamp>/
├── figures/                 captured figures (PNG, optional FIG)
├── report.html              parameters, figures, workspace and log
├── workspace.mat            captured workspace variables
├── parameters.json          parameter records with ids and line numbers
├── run.json                 metadata used by the run history
├── run_script.m             the script copy that actually ran
└── curve_data.csv           optional X/Y export from the Plot tab
```

The original `.m` file is never modified. The tuned script is saved separately as `<name>_tuned.m`.

## 3. How the scanner works

The scanner reads executable code only and skips comments and string contents. It assigns each numeric or logical literal a name, category and recommendation score.

| Source | Detected name |
| --- | --- |
| `m = 1.0;` | `m` |
| `request.gains.eta = 12;` | `request.gains.eta` |
| `request.gain = struct('offset',4,'period',60);` | `request.gain.offset`, `request.gain.period` |
| `window = [1.25 1.5 1.75];` | `window(1)`, `window(2)`, `window(3)` |
| `t = 0:0.01:10;` | `t (start)`, `t (step)`, `t (end)` |
| `flag = true;` | `flag` (logical) |

Use `% @param` to force a literal into the recommended list:

```matlab
gain = 2.0;   % @param controller gain
```

Use `% @ignore` to exclude a false positive from recommendations while keeping it visible under **All numbers**:

```matlab
style.width = 1;   % @ignore line width, not a physical parameter
```

Detection is heuristic. Plot styling, array sizes and indexes can appear in the table. The **All numbers** filter shows everything; choose what to use manually.

## 4. Editing parameters

The table has these columns:

| Column | Meaning |
| --- | --- |
| **Use** | Include the parameter in the next run |
| **Lock** | Keep the original value; new values are ignored |
| **Parameter** | Name inferred by the scanner |
| **Current value** | Value in the source script |
| **New value** | Editable value used by the run |
| **Line** | Source line |
| **Type** | Value category |
| **Description** | Human-readable meaning |
| **Notes** | Code comment or imported annotation |

Useful actions:

- **Bulk edit** (`Ctrl+B`): set values, multiply, add an offset, reset, check/uncheck, lock/unlock, or paste a column from Excel.
- **Undo/redo** (`Ctrl+Z` / `Ctrl+Y`) for table edits, presets and history loads.
- **Presets**: save the current use/new/lock state under a name in `<name>_presets.json`.
- **Sessions**: unsaved edits are stored in `<name>_session.json` and restored when the same script is reopened.
- **Source protection**: if the `.m` file changes after scanning, the app asks you to rescan before running or saving.

## 5. Running and reports

A run uses a temporary copy of the script with your edits. New figures are made invisible, captured, and closed unless **Keep figures** is enabled. The app neutralizes `close all` in the run copy so the figure capture is not interrupted.

The HTML report contains:

- run status, source file, timestamp and elapsed time
- changed parameters, old/new values and annotations
- captured figures
- workspace variable summary
- console output
- links to `parameters.json` and the saved run script

Error messages are mapped back to your original file and line number instead of the temporary copy.

**Save tuned .m** writes a standalone `<name>_tuned.m` and `<name>_tuned_params.json`. A line-by-line diff is shown before writing. The tuned script does not require MATLAB Parameter Studio.

## 6. Batch sweeps

Open **Batch sweep...** and enter values for one or more parameters:

```text
1,2,4              discrete values
0.5 0.75 1         whitespace-separated values
1:0.5:5            colon range
```

Multiple parameters form a Cartesian product. The dialog shows the estimated scenario count and lets you cap it (default 24, maximum 500).

Options:

- **Overlay curve**: choose X/Y variables from the previous workspace; every scenario is drawn on one chart.
- **Parallel**: distribute scenarios over Parallel Computing Toolbox workers. The app chooses a conservative worker count automatically.
- **Seed**: scenarios are seeded from `app.SweepSeed + index` (default `0`), so serial and parallel results are reproducible for the same scenario. Change `app.SweepSeed` for a new replicate.
- **Cancel**: completed scenarios still produce a partial report and metrics CSV.

Output:

```text
parameter_studio_runs/<timestamp>_sweep/
├── run_01/ ... run_NN/      per-scenario scripts, figures, workspace and logs
├── overlay.png              optional overlay curve
├── sweep_report.html        scenario table, metrics and figures
├── sweep_summary.csv        metrics for each scenario/Y variable
├── sweep.json               machine-readable sweep record
└── run.json                 run-history metadata
```

Programmatic sweep:

```matlab
summary = app.runSweepWithValues({'k','c'}, {[4 8], [0.2 0.5]}, 't', {'y'});
```

For stochastic scripts, remember that the script's own `rng` call overrides the scenario seed.

## 7. Project mode

Use **Open project...** when parameters live in several `.m` files:

1. Choose the entry script (for example `run_experiment.m`).
2. The app recursively scans `.m` files under that folder.
3. The parameter table adds a **File** column and a file filter.
4. A run copies the project to a temporary shadow folder, applies edits there, and runs the entry script.
5. The original project is never written to.

The shadow folder excludes `parameter_studio_runs/`, `运行结果/`, `绘图数据缓存/` and similar result folders. It is reused within one MATLAB process and synchronized when `.m` or input files change.

Project mode supports parallel sweeps. It does not support manual parameters or saving a single combined `_tuned.m`.

## 8. Annotations

Use **Generate annotation JSON** to export a template:

- `id`: file + line + column, used for exact matching
- `name`, `value`, `line`, `category`, `note`
- `context`, `contextBefore`, `contextAfter`
- `description` and `unit` for an AI or a human to fill in

Import accepts a simple name map, name + description/unit objects, or the full template:

```jsonc
{ "m": "mass (kg)", "k": "spring stiffness" }
```

```jsonc
{ "m": { "description": "mass", "unit": "kg" } }
```

Matching prefers `id`, then `name + line`, then a unique `name`. Ambiguous duplicate names are skipped and reported. The annotation file is `<name>_annotations.json`; it is loaded automatically when the script is reopened.

## 9. Run history and comparison

**Run history** lists all runs under `parameter_studio_runs/` for the source script. Each row shows time, type, status, changed parameters, elapsed time, figure count and disk usage.

- **Load parameters**: restore a previous run's use/new/lock state.
- **Set as A / Set as B**: choose two runs and generate `compare.html` plus `compare.json`.
- **Compare content**: parameter values, workspace differences (max absolute, RMS, relative), and figures side by side.
- **Clean old runs**: keep the latest 10/30 runs and delete older results. The current run is not deleted.

## 10. Memory and performance

Large simulations can produce large workspaces. Defaults:

- Single variable budget: 100 MB
- Total workspace budget: 512 MB
- Lazy workspace threshold: 32 MB
- Figures: PNG only, 150 dpi
- Parallel workers: automatic, capped at 4

Adjust before a run:

```matlab
app.MaxVariableMB = 200;
app.MaxTotalMB = 1024;
app.LazyWorkspaceMB = 64;
app.SaveFigFiles = false;
app.FigureResolution = 120;
app.NumWorkers = 0;          % automatic
app.MaxWorkers = 4;
app.BackgroundWorkers = 1;
app.KeepParallelPool = false;
```

Project mode copies the project to a temporary shadow folder. Exclude large generated folders in your project if they are not needed as inputs.

## 11. Automation and public API

```matlab
app = MatlabParameterStudio('Visible', 'off', 'Language', 'en');
app.loadFile('demo/demo_simulation.m');
app.setParam('k', 8);
app.toggleLock('m');
app.runCurrent();
report = app.Results.LastReport;
```

Useful methods:

- `app.loadFile(path)`
- `app.loadProject(entryFile)`
- `app.setEntryPoint(entryFile)`
- `app.setParam(name, value)`
- `app.toggleLock(name)`
- `app.runCurrent()`
- `app.runSweepWithValues(names, valueLists, xName, yNames)`
- `app.saveCurrentPreset(name)`, `app.listPresets()`, `app.applyPresetByName(name)`
- `app.exportAnnotationTemplate(path)`, `app.importAnnotations(path)`, `app.clearAnnotations()`
- `app.plotWorkspace(xName, yNames)`, `app.exportCurveCsv()`

Core functions include `mps.scan`, `mps.applyEdits`, `mps.runScript`, `mps.writeReport`, `mps.compareRuns`, `mps.parseSweepValues`, `mps.sweepScenarios`, `mps.writeSweepReport`, `mps.savePreset`, `mps.applyPreset` and `mps.validateValue`.

## 12. Verification and troubleshooting

Run the full local test suite:

```matlab
addpath('tests')
run_tests
```

Or run the environment check, complete test suite and log:

```matlab
mps.preflight()
```

See the [FAQ](faq.md) for common problems, and [Examples](../examples/README.md) for runnable scripts.
