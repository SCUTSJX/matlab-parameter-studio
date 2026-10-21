<div align="center">

[English](README.md) · **简体中文**

# 示例

</div>

> [用户指南](../docs/guide.zh-CN.md) · [FAQ](../docs/faq.zh-CN.md) · [项目 README](../README.zh-CN.md)

这些示例覆盖 MATLAB Parameter Studio 的主要工作流。用应用打开、改一两个参数、运行，然后查看生成的报告。

| 示例 | 工作流 | 推荐尝试的参数 |
| --- | --- | --- |
| [`demo/demo_simulation.m`](../demo/demo_simulation.m) | 基础扫描和运行 | `m`、`k`、`c` |
| [`sweep_demo.m`](sweep_demo.m) | 批量扫参和叠加曲线 | `k`、`c` |
| [`annotated_demo.m`](annotated_demo.m) | `% @param` / `% @ignore` 和注释 | `gain`、`damping`、`frequency` |
| [`project_mode/`](project_mode/) | 多文件项目模式 | `cfg.gain`、`cfg.damping`、`cfg.frequency` |

## 基础示例

```matlab
MatlabParameterStudio
```

打开 `demo/demo_simulation.m`，修改 `m`、`k` 或 `c`，点 **运行**。工作区应包含 `t`、`x`、`y` 和原始参数。

## 扫参示例

打开 `sweep_demo.m`，点 **批量扫描...**，填入：

```text
k: 4,6,8
c: 0.2,0.35
```

选择 `t` 作为 X、`y` 作为 Y，勾选 **叠加曲线**，开始扫描。报告会显示每个 `k`/`c` 组合的曲线和指标。

## 注释示例

打开 `annotated_demo.m`。`% @param` 注释会把 `gain`、`damping`、`frequency`、`tEnd` 强制加入推荐列表；`lineWidth` 被 `% @ignore` 排除。

点 **生成注释 JSON**，让 AI（或自己）填写 `description` 和 `unit`，再导入。**注释** 列和报告末尾会显示这些说明。

## 项目模式示例

1. 打开 `project_mode/config.m`。
2. 点 **入口...**，选择 `project_mode/entry.m`。
3. 修改 `cfg.gain`、`cfg.damping` 或 `cfg.frequency`，点 **运行**。

应用会把整个目录复制到临时影子项目，在副本中应用修改并运行 `entry.m`，原始文件保持不变。

## 输出位置

每次运行会在源文件旁边生成 `parameter_studio_runs/<时间戳>/`，包含 `report.html`、图和工作区。该目录被 Git 忽略。

## 命令行运行

```matlab
app = MatlabParameterStudio('Visible', 'off');
app.loadFile('examples/sweep_demo.m');
app.setParam('k', 8);
app.setParam('c', 0.35);
app.runCurrent();
report = app.Results.LastReport;
```

完整 API 见 [用户指南](../docs/guide.zh-CN.md)。
