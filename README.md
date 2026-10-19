# MATLAB Parameter Studio

> 导入 `.m` 脚本 → 自动扫描可改参数 → 改值/勾选 → 运行 → 出图 + HTML 报告 → 保存调参后的新脚本。

![截图](docs/screenshot.png)

## 它解决什么问题

用 AI 生成 MATLAB 仿真脚本很方便，但后续自己调参很麻烦：想把某个 `1` 改成 `2`，又要让 AI 再跑一遍。

这个工具的思路是：把 `.m` 文件里**所有数字/逻辑字面量**扫描出来，结合赋值、`struct` 字段、数组、范围等上下文给它们起名字，用表格展示和编辑；然后运行脚本、抓取图窗和工作区变量，输出一份 HTML 报告，并把改过的脚本保存成可以直接运行的 `<原名>_tuned.m`。

之后调参不再需要 AI，也不需要记住参数藏在哪一行。

## 快速开始

环境：MATLAB R2022a 或更新（本项目在 R2025a 上开发和测试）。

1. 在 MATLAB 中 `cd` 到本目录：

   ```matlab
   cd('路径/matlab-parameter-studio')
   MatlabParameterStudio
   ```

2. 点“打开 .m 文件”，选择一个脚本（例如 `demo/demo_simulation.m`）。
3. 在左侧“参数”表里修改“新值”，例如：
   - `m`：`1.0` → `2`
   - `k`：`4.0` → `8`
   - `c`：`0.2` → `0.5`
4. 点“运行”。结果写入源文件旁边的：

   ```text
   parameter_studio_runs/<时间戳>/
   ├── figures/fig_01.png, fig_02.png   % 脚本产生的图
   ├── report.html                      % 参数变化 + 图 + 工作区 + 控制台输出
   ├── workspace.mat                    % 本次工作区变量
   ├── parameters.json                  % 本次参数记录
   ├── run_script.m                     % 本次实际运行的脚本副本
   └── curve_data.csv                   % 在“绘图”标签导出的 X/Y 曲线数据
   ```

5. 点“保存调参 .m”，得到可以直接运行的 `<原名>_tuned.m` 和 `<原名>_tuned_params.json`。

## 界面说明

- **参数表**：`使用`（勾选参与运行的参数）、`参数`（推导出的名字）、`当前值`、`新值`（可编辑）、`行`、`类型`、`说明`。
- **筛选**：
  - `推荐参数`：只显示推荐分数较高的参数（默认）。
  - `全部数字`：显示脚本中所有数字字面量，包括绘图样式、数组尺寸、索引等低置信度数字，由你决定是否勾选。
  - `已修改`：只显示本次改过值的参数。
- **源码预览**：点击参数行，下面显示该行上下文的源码。
- **结果图**：下拉选择脚本产生的图，直接预览。
- **工作区**：变量名、类型、大小、最小/最大值和预览。
- **绘图**：选择工作区的数值向量作为 X/Y 轴，自己画一张图；点“保存图并更新报告”会把这张图写进 HTML 报告；点“导出曲线 CSV”会把当前 X/Y 数据写成 `curve_data.csv`（UTF-8，带表头），方便直接拿去 Excel/Python/论文里用。
- **日志**：脚本的控制台输出。
- **保存调参 .m**：生成带修改值（并在文件末尾注明每个改动）的可直接运行脚本。
- **导出参数**：把当前识别出的所有参数导出为 JSON。

## 能识别什么

扫描器只处理可执行代码，跳过字符串和注释。它会尽量推断有意义的参数名：

| 源码写法 | 识别结果 |
| --- | --- |
| `m = 1.0;` | `m` |
| `request.gains.eta = 12;` | `request.gains.eta` |
| `request.gain = struct('offset',4,'period',60);` | `request.gain.offset`、`request.gain.period` |
| 嵌套 `struct('gains',struct('eta',12,...))` | `...gains.eta` |
| `window = [1.25 1.5 1.75];` | `window(1)`、`window(2)`、`window(3)` |
| `t = 0:0.01:10;` | `t (起点)`、`t (步长)`、`t (终点)` |
| `flag = true;` | `flag`（逻辑值） |
| `...` 续行的多行 struct | 与单行 struct 一样命名 |
| `x = 1; % @param` | 强制标记为参数（即使它在低置信度分类里） |

`% @param` 是给 AI 生成代码准备的“显式标记”：如果你希望某个数字永远出现在推荐列表里，在该行或上一行注释里写 `@param` 即可。

### 推荐分数

扫描器会给每个数字一个分数。命名清晰、带注释、位于赋值右侧的数字分高；绘图样式（`LineWidth`、`FontSize`）、布局（`figure('Position',...)`）、数组尺寸（`zeros(1,1000)`）、索引（`x(:,1)`）和循环控制数字分低，默认不勾选。你可以在“全部数字”里查看并手动勾选。

## 工作原理

```text
.m 文件
  ↓ mps.scan
参数列表（名字、当前值、行号、列号、类别、分数）
  ↓ 用户在表格里编辑
mps.applyEdits
  ↓ 生成一个临时脚本（放在源文件旁边，保证相对路径可用；
  ↓ 运行时把 close all 换成无害语句，保住图窗）
mps.runScript → mps.executeScript → mps.captureWorkspace
  ↓ 隔离工作区运行，抓取新图窗、变量、控制台输出
mps.writeReport
  ↓ HTML 报告 + parameters.json
保存调参 .m
```

- **不修改原文件**：所有修改只写入临时副本和另存的 `_tuned.m`。
- **隔离工作区**：脚本在独立函数工作区里运行，脚本里的 `clear` 不会清掉界面，也不会污染你的 MATLAB 基础工作区。
- **保护界面**：界面图窗设置为 `HandleVisibility='off'`，并在运行副本里中和 `close all`，这样抓到图窗的同时不会把界面关掉。
- **相对路径**：临时脚本写在源文件所在目录，`run` 执行时的当前目录就是源目录，`load('data.mat')` 这类写法可以正常工作；运行结束后临时脚本会被删除，副本保存在输出目录。

## 在 GitHub 上和类似项目的对比

> 调研时间：2026-10。下面几类最接近的现成项目/工具，以及它们的边界。

| 项目 / 工具 | 类型 | 和你需求的关系 |
| --- | --- | --- |
| [SLX-Studio](https://github.com/savellonirourou107-hue/SLX-Studio)（115★） | Python + Electron/TypeScript 的轻量 MATLAB/Simulink IDE | **最接近**：能编辑/运行 `.m`、查看工作区变量、抓图；对 Simulink 块参数有 Sweep 面板。但它没有“扫描任意 `.m` 里的数字并生成参数表/HTML 报告/调参后脚本”这条链路；Sweep 面向 `.slx` 块参数，不是脚本字面量。 |
| [matlab/matlab-mcp-server](https://github.com/matlab/matlab-mcp-server)（1.7k★） | 官方 MCP Server | 让 Claude/VS Code 等 AI 直接运行 MATLAB。是“让 AI 跑”的路线，不是“人工在表格里调参”。 |
| [bertnp/parampack](https://github.com/bertnp/parampack)（2★） | MATLAB 库 | 定义和遍历参数扫描（`parampack`），适合写脚本做批量扫描，但没有导入/识别/GUI/报告。 |
| [hsharrison/sysviewer](https://github.com/hsharrison/sysviewer)（1★） | MATLAB GUI | 给动力系统流场图加滑条调参，领域特定，不通用。 |
| Experiment Manager（MATLAB 内置 App） | MATLAB App | 可以为 MATLAB 代码创建实验、用不同参数值运行并对比结果。需要手工定义实验/参数，输出偏对比表格，不如 HTML 报告灵活，也没有“自动扫描任意脚本数字”。 |
| Live Editor 交互控件（MATLAB 内置） | Live Script | 可以给变量加滑条/输入框/下拉框，改完自动重跑。需要手工给每个参数添加控件，适合少量固定参数。 |
| Simulink Design Optimization（MathWorks 付费工具箱） | 商业工具箱 | 参数估计、响应优化、敏感性分析；面向 Simulink 模型，付费且配置较重。 |

结论：**没有一个现成项目完全覆盖“任意 `.m` 脚本 → 自动扫描参数 → 表格调参 → 运行 → 图 + HTML 报告 → 可直接运行的调参脚本”**。SLX-Studio 是最接近的邻居，如果你主要做 Simulink 模型编辑，建议先试它；如果你主要是 AI 生成的 `.m` 仿真脚本，本项目就是为这个场景写的。

## 目录结构

```text
MatlabParameterStudio.m      启动入口（函数）
+mps/App.m                   界面与交互
+mps/scan.m                  .m 扫描器（参数识别与打分）
+mps/applyEdits.m            替换参数、生成运行副本
+mps/runScript.m             运行并抓取图窗/工作区/日志
+mps/executeScript.m         隔离工作区执行脚本
+mps/captureWorkspace.m      无污染地复制调用者工作区
+mps/summarizeWorkspace.m    工作区变量摘要
+mps/writeReport.m           HTML 报告 + parameters.json
+mps/validateValue.m         新值校验（只允许数值表达式）
demo/demo_simulation.m       弹簧-阻尼示例
demo/relative_demo.m         相对路径加载示例
tests/run_tests.m            自测
```

## 测试

在 MATLAB 中：

```matlab
addpath('tests')
run_tests
```

测试覆盖：参数识别、数值校验、改值运行、图窗/工作区抓取、报告生成、多行嵌套 `struct`、`% @param` 标记、函数文件扫描。

## 已知限制

- 只支持 `.m` 文本脚本，不支持 `.mlx` Live Script 和 `.slx` Simulink 模型（`.slx` 是路线图里的第一项）。
- 参数识别是**启发式**的：无法 100% 自动判断“哪个数字是物理参数、哪个是绘图样式”。默认推荐只是一个起点，请配合“全部数字”和 `% @param` 使用。
- 函数文件（第一行是 `function`）可以扫描和保存，但不能直接运行；请打开调用它的脚本再运行。
- 运行时会执行脚本里的任意 MATLAB 代码，只对你自己信任的脚本使用。
- 新值只允许数值表达式（数字、`pi`、`Inf`、`NaN`、数组、范围和四则运算），不允许函数调用或字符串，避免从参数输入执行任意代码。
- 运行副本会临时写到源文件所在目录，以保证相对数据路径可用；如果该目录只读，会退回到输出目录（此时相对路径可能失效）。
- 运行副本会把 `close all` 替换成无害语句，以便抓到图窗；保存出来的 `_tuned.m` 保留原来的 `close all`。
- 对于一个文件里名字重复的参数（例如两个 `validation_noise.switch_time`），表格里会显示为同名不同值的两行，请结合“行”列区分。

## 路线图

- `.slx` 模型支持：用 `find_system` / `get_param` 列出模块的可调数值参数，运行 `sim`，抓取 `SimulationOutput` 曲线。
- 参数集导入：加载之前导出的 JSON，一键恢复一组参数。
- 批量扫描：一个参数给出多个值，一次运行多组并叠图对比。
- 打包成 MATLAB App / Toolbox（`.mlapp` / `.mltbx`），双击即用。
- 更智能的命名：结合单位注释、变量使用频率、`arguments` 块默认值等。

## 安全说明

- 工具本身不联网、不上传任何文件。
- 扫描阶段只读文本；运行阶段执行脚本，等同于你在 MATLAB 里自己运行该脚本。
- 生成的 HTML 报告是本地静态文件，图片使用相对路径。

## License

MIT
