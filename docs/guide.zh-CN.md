<div align="center">

[English](guide.md) · **简体中文**

# 用户指南

</div>

> [项目 README](../README.zh-CN.md) · [示例](../examples/README.zh-CN.md) · [FAQ](faq.zh-CN.md)

本文覆盖完整流程：安装、扫描脚本、编辑和运行参数、查看报告、批量扫参、项目模式，以及在 MATLAB 中自动调用。

## 1. 安装和启动

**环境要求：** MATLAB R2023b 或更新版本。开发和测试使用 R2025a。Parallel Computing Toolbox 是可选项，用于后台运行和并行扫参。

```matlab
cd('路径/matlab-parameter-studio')
install                 % 仅当前 MATLAB 会话生效
% install('Save')       % 写入 MATLAB path
```

启动界面：

```matlab
MatlabParameterStudio            % 中文界面（默认）
MatlabParameterStudioEnglish     % 英文界面
MatlabParameterStudio('Language','en')
```

无界面自动化运行：

```matlab
app = MatlabParameterStudio('Visible', 'off', 'Language', 'en');
```

## 2. 第一次运行

1. 点 **打开 .m 文件**，选择脚本，例如 `demo/demo_simulation.m`。
2. 在参数表中修改 **新值**；用 **使用** 列决定该参数是否参与运行。
3. 点 **运行**。
4. 打开生成的 HTML 报告，或点 **保存调参 .m** 保存可直接运行的脚本。

结果写入源脚本旁边：

```text
parameter_studio_runs/<时间戳>/
├── figures/                 抓取到的图（PNG，可选 FIG）
├── report.html              参数、图、工作区和日志
├── workspace.mat            本次工作区变量
├── parameters.json          含 id 和行号的参数记录
├── run.json                 运行历史元数据
├── run_script.m             实际运行的脚本副本
└── curve_data.csv           “绘图”标签导出的 X/Y 数据
```

原始 `.m` 文件不会被修改；调参结果另存为 `<原名>_tuned.m`。

## 3. 扫描器如何工作

扫描器只读取可执行代码，跳过注释和字符串内容，并为每个数字/逻辑字面量生成名称、类别和推荐分数。

| 源码写法 | 识别结果 |
| --- | --- |
| `m = 1.0;` | `m` |
| `request.gains.eta = 12;` | `request.gains.eta` |
| `request.gain = struct('offset',4,'period',60);` | `request.gain.offset`、`request.gain.period` |
| `window = [1.25 1.5 1.75];` | `window(1)`、`window(2)`、`window(3)` |
| `t = 0:0.01:10;` | `t (起点)`、`t (步长)`、`t (终点)` |
| `flag = true;` | `flag`（逻辑值） |

用 `% @param` 强制把数字加入推荐列表：

```matlab
gain = 2.0;   % @param 控制器增益
```

用 `% @ignore` 排除误报，它仍会在 **全部数字** 中显示：

```matlab
style.width = 1;   % @ignore 线宽，不是物理参数
```

参数识别是启发式的。绘图样式、数组尺寸、索引等也可能出现在表中；用 **全部数字** 查看并手动勾选。

## 4. 编辑参数

参数表列的含义：

| 列 | 含义 |
| --- | --- |
| **使用** | 是否参与下一次运行 |
| **锁定** | 固定原值，运行和保存时忽略新值 |
| **参数** | 扫描器推断的名称 |
| **当前值** | 源脚本中的值 |
| **新值** | 本次运行使用的可编辑值 |
| **行** | 源码行号 |
| **类型** | 值的类别 |
| **说明** | 人类可读的含义 |
| **注释** | 代码注释或导入的 AI 注释 |

常用操作：

- **批量修改**（`Ctrl+B`）：批量设值、乘系数、加偏移、恢复原值、勾选/取消勾选、锁定/解锁，或从 Excel 粘贴一列。
- **撤销/重做**（`Ctrl+Z` / `Ctrl+Y`）：覆盖表格修改、参数集载入和历史参数载入。
- **参数集**：把当前使用/新值/锁定状态保存为 `<文件名>_presets.json`。
- **会话恢复**：未运行的修改写入 `<文件名>_session.json`，重新打开同一脚本时自动恢复。
- **源文件保护**：扫描后 `.m` 被外部修改时，运行或保存前会提示重新扫描。

## 5. 运行和报告

运行会使用带修改的临时脚本副本。新图窗默认不可见，抓取后关闭；勾选 **保留结果图窗** 可以保留窗口。运行副本会把 `close all` 中和掉，避免图窗在抓取前被关闭。

HTML 报告包括：

- 运行状态、源文件、时间戳和耗时
- 参数变化、原值/新值和注释
- 抓取到的图
- 工作区变量摘要
- 控制台输出
- `parameters.json` 和运行脚本的链接

错误信息会映射回原始文件和行号，而不是临时脚本。

**保存调参 .m** 会生成独立的 `<原名>_tuned.m` 和 `<原名>_tuned_params.json`，写入前显示逐行 diff。调参脚本不需要 MATLAB Parameter Studio 就能运行。

## 6. 批量扫参

点 **批量扫描...**，给一个或多个参数填写扫描值：

```text
1,2,4              离散值
0.5 0.75 1         空格分隔的值
1:0.5:5            冒号范围
```

多个参数会做笛卡尔积。窗口会显示预计组数，并可设置上限（默认 24，最大 500）。

选项：

- **叠加曲线**：从上次工作区选择 X/Y，把所有场景画在同一张图上。
- **并行运行**：把场景分配到 Parallel Computing Toolbox worker；应用会自动选择保守的 worker 数。
- **随机种子**：每个场景使用 `app.SweepSeed + 序号` 作为种子（默认 `0`），因此同一场景的串行/并行结果可复现。需要新的重复实验时修改 `app.SweepSeed`。
- **取消**：已完成的场景仍会生成部分报告和指标 CSV。

输出：

```text
parameter_studio_runs/<时间戳>_sweep/
├── run_01/ ... run_NN/      每组脚本、图、工作区和日志
├── overlay.png              可选的叠加曲线
├── sweep_report.html        组表、指标和图
├── sweep_summary.csv        每组/每个 Y 的指标
├── sweep.json               机器可读的扫描记录
└── run.json                 运行历史元数据
```

命令行扫参：

```matlab
summary = app.runSweepWithValues({'k','c'}, {[4 8], [0.2 0.5]}, 't', {'y'});
```

随机脚本如果在内部调用 `rng`，会覆盖场景种子。

## 7. 项目模式

参数分布在多个 `.m` 文件时，用 **打开项目...**：

1. 选择入口脚本（例如 `run_experiment.m`）。
2. 应用递归扫描入口脚本所在目录下的 `.m` 文件。
3. 参数表增加 **文件** 列和文件筛选。
4. 运行时把项目复制到临时影子目录，在副本中应用修改并运行入口脚本。
5. 原项目源码不会被写入。

影子目录会跳过 `parameter_studio_runs/`、`运行结果/`、`绘图数据缓存/` 等结果目录，并在同一 MATLAB 进程内复用，只同步变化的文件。

项目模式支持并行扫参；暂不支持手动参数和保存单个合并的 `_tuned.m`。

## 8. AI 注释

点 **生成注释 JSON** 导出模板，字段包括：

- `id`：文件 + 行 + 列，用于精确匹配
- `name`、`value`、`line`、`category`、`note`
- `context`、`contextBefore`、`contextAfter`
- 待填写的 `description`（含义）和 `unit`（单位）

导入支持三种格式：名称到含义的简单映射、名称到 `description/unit` 对象、或完整模板：

```jsonc
{ "m": "质量 (kg)", "k": "弹簧刚度" }
```

```jsonc
{ "m": { "description": "质量", "unit": "kg" } }
```

匹配顺序：`id` → `name + line` → 唯一 `name`；同名参数会跳过并报告。注释文件为 `<文件名>_annotations.json`，重新打开脚本时自动载入。

## 9. 运行历史和对比

**运行历史**列出源脚本旁边 `parameter_studio_runs/` 中的所有运行。每行显示时间、类型、状态、修改的参数、耗时、图数和磁盘占用。

- **载入参数**：恢复某次运行的使用/新值/锁定状态。
- **设为基准 A / 设为当前 B**：选择两次运行，生成 `compare.html` 和 `compare.json`。
- **对比内容**：参数值、工作区差异（最大绝对差、RMS、相对差）和左右并排的结果图。
- **清理旧运行**：保留最近 10/30 次，删除更早的结果；当前运行不会被删除。

## 10. 内存和性能

大型仿真可能产生大工作区。默认值：

- 单个变量预算：100 MB
- 工作区总预算：512 MB
- 懒加载阈值：32 MB
- 图：只保存 PNG，150 dpi
- 并行 worker：自动，最多 4 个

运行前可以调整：

```matlab
app.MaxVariableMB = 200;
app.MaxTotalMB = 1024;
app.LazyWorkspaceMB = 64;
app.SaveFigFiles = false;
app.FigureResolution = 120;
app.NumWorkers = 0;          % 自动
app.MaxWorkers = 4;
app.BackgroundWorkers = 1;
app.KeepParallelPool = false;
```

项目模式会把项目复制到临时影子目录；不需要作为输入的大结果目录应尽量排除。

## 11. 自动化与公开 API

```matlab
app = MatlabParameterStudio('Visible', 'off', 'Language', 'en');
app.loadFile('demo/demo_simulation.m');
app.setParam('k', 8);
app.toggleLock('m');
app.runCurrent();
report = app.Results.LastReport;
```

常用方法：

- `app.loadFile(path)`
- `app.loadProject(entryFile)`
- `app.setEntryPoint(entryFile)`
- `app.setParam(name, value)`
- `app.toggleLock(name)`
- `app.runCurrent()`
- `app.runSweepWithValues(names, valueLists, xName, yNames)`
- `app.saveCurrentPreset(name)`、`app.listPresets()`、`app.applyPresetByName(name)`
- `app.exportAnnotationTemplate(path)`、`app.importAnnotations(path)`、`app.clearAnnotations()`
- `app.plotWorkspace(xName, yNames)`、`app.exportCurveCsv()`

核心函数包括 `mps.scan`、`mps.applyEdits`、`mps.runScript`、`mps.writeReport`、`mps.compareRuns`、`mps.parseSweepValues`、`mps.sweepScenarios`、`mps.writeSweepReport`、`mps.savePreset`、`mps.applyPreset`、`mps.validateValue`。

## 12. 验证和排查

运行完整本地测试：

```matlab
addpath('tests')
run_tests
```

或运行环境检查 + 完整测试 + 日志：

```matlab
mps.preflight()
```

常见问题见 [FAQ](faq.zh-CN.md)，可运行示例见 [示例](../examples/README.zh-CN.md)。
