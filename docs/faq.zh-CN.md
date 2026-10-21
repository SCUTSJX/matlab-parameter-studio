<div align="center">

[English](faq.md) · **简体中文**

# 常见问题

</div>

> [用户指南](guide.zh-CN.md) · [示例](../examples/README.zh-CN.md) · [项目 README](../README.zh-CN.md)

### 需要哪个 MATLAB 版本？

MATLAB **R2023b 或更新版本**。当前在 R2025a 上开发和测试。应用使用多选表格和可取消进度框等 R2023b 时代的 UI 能力。

### 会修改我的原始脚本吗？

不会。修改只写入临时副本；点 **保存调参 .m** 时会另存为 `<原名>_tuned.m`。正常运行和保存不会写入原始 `.m` 文件。

### 支持 `.mlx` Live Script 或 `.slx` Simulink 模型吗？

不支持。目前只处理 `.m` 文本脚本。Simulink 模块参数和 Live Script 不在 1.0 的范围内。

### 为什么有些数字没有出现在推荐列表？

参数识别是启发式的。绘图样式、数组尺寸、索引和低置信度数字会被刻意打低分。用 **全部数字** 查看所有字面量，用 `% @param` 强制加入推荐列表，用 `% @ignore` 排除误报。

### 为什么参数名和变量名不完全一样？

扫描器会从赋值、`struct` 字段、数组和范围推断名称。复杂表达式可能使用位置名或附近注释。给变量改一个清晰的名字，或在行尾写 `% @param 名称`，可以让意图更明确。

### 函数文件能直接运行吗？

不能直接运行。函数文件可以扫描和保存，但需要打开调用它的脚本。如果它是配置函数，可以打开该函数，点 **入口...** 选择项目入口脚本，然后运行入口脚本。

### 必须安装 Parallel Computing Toolbox 吗？

不是必须。没有 PCT 时应用仍可使用，只是后台运行和并行扫参不可用，扫参会串行执行。

### 为什么会出现很多 MATLAB 进程？

本地 `parpool('Processes')` 会按物理核数启动 worker，再加一个 MATLAB 客户端。可用 `app.NumWorkers` 或 `app.MaxWorkers` 限制 worker 数，并用 `app.KeepParallelPool = false` 在运行结束后关闭并行池。要立即关闭现有并行池：

```matlab
delete(gcp('nocreate'))
```

### 扫参结果可复现吗？

在 `app.SweepSeed` 固定的情况下可以。第 k 个场景使用 `SweepSeed + k - 1`，串行和并行路径对同一场景使用相同种子。如果脚本内部自己调用 `rng`，会覆盖场景种子。

### 运行结果、会话、参数集和注释存在哪里？

都在源脚本旁边：

- `parameter_studio_runs/`：运行结果
- `<文件名>_session.json`：未运行的表格状态
- `<文件名>_presets.json`：命名参数集
- `<文件名>_manual.json`：手动添加的参数
- `<文件名>_annotations.json`：AI/人工注释

运行结果和本地状态默认被 Git 忽略。

### 为什么 `git status` 里看不到 `_tuned.m` 或 `_params.json`？

它们是生成物，已被 `.gitignore` 忽略。如果确实要版本化某次调参结果，可以强制加入：

```bash
git add -f demo/demo_simulation_tuned.m
git add -f demo/demo_simulation_tuned_params.json
```

### HTML 报告能单独发给别人吗？

可以。报告使用相对路径引用 `figures/` 文件夹，所以要分享整个运行目录，而不是只发 `report.html`。

### 应用会上传代码或结果吗？

不会。工具不联网、不上传文件、不带遥测。运行脚本仍然会执行脚本里的 MATLAB 代码，所以只运行你信任的脚本。

### 怎么切换中英文界面？

```matlab
MatlabParameterStudioEnglish
% 或
MatlabParameterStudio('Language', 'en')
% 切回中文
mps.setLanguage('zh')
```

### 怎么对比两次运行？

打开 **运行历史**，选中一次运行点 **设为基准 A**，再选另一次点 **设为当前 B**，然后点 **对比 A / B**。结果写入 B 运行目录下的 `compare.html` 和 `compare.json`。

### 怎么清理旧结果？

打开 **运行历史**，点 **清理旧运行...**。可以保留最近 10 次或 30 次；当前运行不会被删除。

### 扫描器漏掉的参数怎么补？

点 **添加参数...**，输入合法的 MATLAB 变量名和数值。它会保存到 `<文件名>_manual.json`，运行脚本时作为赋值语句插到最前面。项目模式不支持手动参数。

### 为什么报告里的工作区变量比实际少？

工作区捕获有单变量和总内存预算（`MaxVariableMB`、`MaxTotalMB`）。超大变量会被跳过并写入日志。超过 `LazyWorkspaceMB` 时采用懒加载，把工作区写入 `workspace.mat`，界面只保留摘要。

### 怎么验证安装是否正常？

```matlab
addpath('tests')
run_tests
```

需要环境检查 + 完整测试 + 时间戳日志时：

```matlab
mps.preflight()
```

### 遇到其他问题怎么办？

提交 issue 时请附上 MATLAB 版本、执行的命令、源脚本（或最小复现）、错误文本和相关日志。`logs/` 下的 preflight 日志很有用，但分享前请先检查本地路径。
