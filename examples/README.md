<div align="center">

**English** · [简体中文](README.zh-CN.md)

# Examples

</div>

> [User guide](../docs/guide.md) · [FAQ](../docs/faq.md) · [Project README](../README.md)

These examples exercise the main workflows of MATLAB Parameter Studio. Open them with the app, edit one or two parameters, run them, and inspect the generated report.

| Example | Workflow | Suggested parameters |
| --- | --- | --- |
| [`demo/demo_simulation.m`](../demo/demo_simulation.m) | Basic scanning and running | `m`, `k`, `c` |
| [`sweep_demo.m`](sweep_demo.m) | Batch sweep and overlay curve | `k`, `c` |
| [`annotated_demo.m`](annotated_demo.m) | `% @param` / `% @ignore` and annotations | `gain`, `damping`, `frequency` |
| [`project_mode/`](project_mode/) | Multi-file project mode | `cfg.gain`, `cfg.damping`, `cfg.frequency` |

## Basic demo

```matlab
MatlabParameterStudioEnglish
```

Open `demo/demo_simulation.m`, change `m`, `k` or `c`, and click **Run**. The workspace should contain `t`, `x`, `y` and the original parameters.

## Sweep demo

Open `sweep_demo.m`, then click **Batch sweep...** and enter:

```text
k: 4,6,8
c: 0.2,0.35
```

Select `t` as X and `y` as Y, enable **Overlay curve**, and start the sweep. The report shows one curve per `k`/`c` combination plus metrics.

## Annotation demo

Open `annotated_demo.m`. The `% @param` comments force `gain`, `damping`, `frequency` and `tEnd` into the recommended list; `lineWidth` is excluded by `% @ignore`.

Click **Generate annotation JSON**, let an AI (or yourself) fill `description` and `unit`, then import it. The **Notes** column and the report footer will show the annotations.

## Project mode demo

1. Open `project_mode/config.m`.
2. Click **Entry...** and choose `project_mode/entry.m`.
3. Change `cfg.gain`, `cfg.damping` or `cfg.frequency` and click **Run**.

The app copies the folder to a temporary shadow project, applies the edits there, and runs `entry.m`. The original files remain unchanged.

## Expected output

Each run creates `parameter_studio_runs/<timestamp>/` beside the source file with `report.html`, figures and `workspace.mat`. These folders are ignored by Git.

## Running from the command line

```matlab
app = MatlabParameterStudio('Visible', 'off');
app.loadFile('examples/sweep_demo.m');
app.setParam('k', 8);
app.setParam('c', 0.35);
app.runCurrent();
report = app.Results.LastReport;
```

See the [user guide](../docs/guide.md) for the full API.
