function h = buildAppUI(cb)
%BUILDAPPUI Create every control in the main window.
%
%   h = mps.buildAppUI(callbacks) returns a struct of UI handles.  App
%   adopts the fields as its own properties, while the event handlers stay
%   in mps.App.  callbacks is a struct of function handles (see
%   mps.App.uiCallbacks).

    h = struct();

    h.UIFigure = uifigure('Name', 'MATLAB Parameter Studio', ...
        'Position', [80 60 1340 840]);
    try
        h.UIFigure.Theme = 'light';   % R2025a+
    catch
    end
    h.UIFigure.CloseRequestFcn = @(s, e) cb.onClose();
    h.UIFigure.KeyPressFcn = @(s, e) cb.onKeyPress(e);

    root = uigridlayout(h.UIFigure, [3 1]);
    root.RowHeight = {48, '1x', 26};
    root.Padding = [10 10 10 8];
    root.RowSpacing = 8;

    tb = uigridlayout(root, [1 11]);
    tb.Layout.Row = 1;
    tb.ColumnWidth = {108, '1x', 88, 78, 132, 100, 110, 110, 100, 90, 90};
    tb.Padding = [0 0 0 0];
    tb.ColumnSpacing = 6;

    h.OpenButton = uibutton(tb, 'Text', '打开 .m 文件', ...
        'ButtonPushedFcn', @(s, e) cb.onOpen());
    h.OpenButton.Layout.Column = 1;

    h.FileLabel = uilabel(tb, 'Text', '未打开文件', ...
        'FontColor', [0.45 0.45 0.45], 'Interpreter', 'none');
    h.FileLabel.Layout.Column = 2;

    h.RescanButton = uibutton(tb, 'Text', '重新扫描', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onRescan());
    h.RescanButton.Layout.Column = 3;

    h.RunButton = uibutton(tb, 'Text', '运行', ...
        'Enable', 'off', 'FontWeight', 'bold', ...
        'BackgroundColor', [0.18 0.45 0.85], ...
        'FontColor', [1 1 1], ...
        'ButtonPushedFcn', @(s, e) cb.onRun());
    h.RunButton.Layout.Column = 4;

    h.SaveButton = uibutton(tb, 'Text', '保存调参 .m', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onSaveTuned());
    h.SaveButton.Layout.Column = 5;

    h.ReportButton = uibutton(tb, 'Text', '打开报告', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onOpenReport());
    h.ReportButton.Layout.Column = 6;

    h.FolderButton = uibutton(tb, 'Text', '打开结果文件夹', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onOpenFolder());
    h.FolderButton.Layout.Column = 7;

    h.ExportButton = uibutton(tb, 'Text', '导出参数 JSON', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onExportParams());
    h.ExportButton.Layout.Column = 8;

    h.CloseFiguresButton = uibutton(tb, 'Text', '关闭结果图窗', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onCloseFigures());
    h.CloseFiguresButton.Layout.Column = 9;

    h.CompareButton = uibutton(tb, 'Text', '运行历史', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onRunHistory());
    h.CompareButton.Layout.Column = 10;

    h.HelpButton = uibutton(tb, 'Text', '快速上手', ...
        'ButtonPushedFcn', @(s, e) cb.onHelp());
    h.HelpButton.Layout.Column = 11;

    main = uigridlayout(root, [1 2]);
    main.Layout.Row = 2;
    main.ColumnWidth = {'1x', '0.72x'};
    main.Padding = [0 0 0 0];
    main.ColumnSpacing = 8;

    lp = uipanel(main, 'Title', '参数', 'FontWeight', 'bold');
    lp.Layout.Column = 1;
    lg = uigridlayout(lp, [5 1]);
    lg.RowHeight = {34, 30, 30, '1x', 96};
    lg.Padding = [8 8 8 8];
    lg.RowSpacing = 6;

    fg = uigridlayout(lg, [1 6]);
    fg.Layout.Row = 1;
    fg.ColumnWidth = {120, '1x', 150, 92, 92, 104};
    fg.Padding = [0 0 0 0];
    fg.ColumnSpacing = 6;

    h.FilterDrop = uidropdown(fg, ...
        'Items', {'推荐参数', '全部数字', '已修改'}, ...
        'Value', '推荐参数', ...
        'ValueChangedFcn', @(s, e) cb.refreshTable());
    h.FilterDrop.Layout.Column = 1;

    h.SearchField = uieditfield(fg, 'text', ...
        'Placeholder', '搜索参数名/说明/行号', ...
        'ValueChangedFcn', @(s, e) cb.refreshTable());
    h.SearchField.Layout.Column = 2;

    h.CountLabel = uilabel(fg, 'Text', '0 / 0', ...
        'HorizontalAlignment', 'right', ...
        'FontColor', [0.4 0.4 0.4]);
    h.CountLabel.Layout.Column = 3;

    h.SelectAllButton = uibutton(fg, 'Text', '全选推荐', ...
        'ButtonPushedFcn', @(s, e) cb.onSelectAll());
    h.SelectAllButton.Layout.Column = 4;

    h.ResetButton = uibutton(fg, 'Text', '重置新值', ...
        'ButtonPushedFcn', @(s, e) cb.onReset());
    h.ResetButton.Layout.Column = 5;

    h.BulkButton = uibutton(fg, 'Text', '批量修改...', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onBulkEdit());
    h.BulkButton.Layout.Column = 6;

    ag = uigridlayout(lg, [1 7]);
    ag.Layout.Row = 2;
    ag.ColumnWidth = {130, '1x', 96, 96, 96, 120, 104};
    ag.Padding = [0 0 0 0];
    ag.ColumnSpacing = 6;

    h.AnnotateTemplateButton = uibutton(ag, ...
        'Text', '生成注释 JSON', 'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onWriteAnnotationTemplate());
    h.AnnotateTemplateButton.Layout.Column = 1;

    h.AnnotationStatus = uilabel(ag, 'Text', '未导入注释', ...
        'FontColor', [0.4 0.4 0.4]);
    h.AnnotationStatus.Layout.Column = 2;

    h.ImportAnnotationButton = uibutton(ag, ...
        'Text', '导入注释', 'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onImportAnnotations());
    h.ImportAnnotationButton.Layout.Column = 3;

    h.ClearAnnotationButton = uibutton(ag, ...
        'Text', '清空注释', 'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onClearAnnotations());
    h.ClearAnnotationButton.Layout.Column = 4;

    h.LockButton = uibutton(ag, ...
        'Text', '锁定选中', 'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onToggleLock());
    h.LockButton.Layout.Column = 5;

    h.KeepFiguresCheck = uicheckbox(ag, ...
        'Text', '保留结果图窗', 'Value', false);
    h.KeepFiguresCheck.Layout.Column = 6;

    h.BackgroundCheck = uicheckbox(ag, ...
        'Text', '后台运行', 'Value', false);
    h.BackgroundCheck.Layout.Column = 7;
    if ~license('test', 'Distrib_Computing_Toolbox')
        h.BackgroundCheck.Enable = 'off';
    end

    pg2 = uigridlayout(lg, [1 8]);
    pg2.Layout.Row = 3;
    pg2.ColumnWidth = {145, '1x', 96, 60, 60, 92, 88, 64};
    pg2.Padding = [0 0 0 0];
    pg2.ColumnSpacing = 6;

    h.PresetDrop = uidropdown(pg2, 'Items', {'(无参数集)'}, ...
        'Value', '(无参数集)');
    h.PresetDrop.Layout.Column = 1;

    h.PresetNameField = uieditfield(pg2, 'text', ...
        'Placeholder', '新参数集名称，如 基线 / 高刚度');
    h.PresetNameField.Layout.Column = 2;

    h.PresetSaveButton = uibutton(pg2, 'Text', '保存为参数集', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onSavePreset());
    h.PresetSaveButton.Layout.Column = 3;

    h.PresetLoadButton = uibutton(pg2, 'Text', '载入', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onLoadPreset());
    h.PresetLoadButton.Layout.Column = 4;

    h.PresetDeleteButton = uibutton(pg2, 'Text', '删除', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onDeletePreset());
    h.PresetDeleteButton.Layout.Column = 5;

    h.SweepButton = uibutton(pg2, 'Text', '批量扫描...', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onOpenSweep());
    h.SweepButton.Layout.Column = 6;

    h.ManualButton = uibutton(pg2, 'Text', '添加参数...', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onAddManualParam());
    h.ManualButton.Layout.Column = 7;

    h.EntryButton = uibutton(pg2, 'Text', '入口...', ...
        'Enable', 'off', ...
        'ButtonPushedFcn', @(s, e) cb.onChooseEntry());
    h.EntryButton.Layout.Column = 8;

    h.Table = uitable(lg, ...
        'ColumnName', {'使用', '锁定', '参数', '当前值', '新值', '行', '类型', '说明', '注释'}, ...
        'ColumnEditable', [true true false false true false false false false], ...
        'ColumnFormat', {'logical', 'logical', 'char', 'char', 'char', 'numeric', 'char', 'char', 'char'}, ...
        'ColumnWidth', {40, 46, 160, 70, 70, 34, 68, 110, '1x'}, ...
        'RowName', [], ...
        'CellEditCallback', @(s, e) cb.onCellEdit(e), ...
        'CellSelectionCallback', @(s, e) cb.onCellSelect(e));
    h.Table.Layout.Row = 4;
    try
        h.Table.Multiselect = 'on';   % R2023b+
    catch
    end
    try
        h.Table.Tooltip = ...
            '双击“参数”或“行”列，在 MATLAB 编辑器中打开对应行';
        h.Table.DoubleClickedFcn = @(s, e) cb.onOpenInEditor(e);
    catch
    end

    sourceGrid = uigridlayout(lg, [1 3]);
    sourceGrid.Layout.Row = 5;
    sourceGrid.ColumnWidth = {'1x', 64, 64};
    sourceGrid.Padding = [0 0 0 0];
    sourceGrid.ColumnSpacing = 6;
    h.SourcePreview = uitextarea(sourceGrid, 'Editable', 'off', ...
        'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});
    h.UndoButton = uibutton(sourceGrid, 'Text', '撤销', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.undo());
    h.UndoButton.Layout.Column = 2;
    h.RedoButton = uibutton(sourceGrid, 'Text', '重做', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.redo());
    h.RedoButton.Layout.Column = 3;

    tg = uitabgroup(main);
    tg.Layout.Column = 2;

    t1 = uitab(tg, 'Title', '结果图');
    rg = uigridlayout(t1, [2 2]);
    rg.RowHeight = {32, '1x'};
    rg.ColumnWidth = {'1x', 110};
    rg.Padding = [8 8 8 8];
    rg.RowSpacing = 6;

    h.FigureDrop = uidropdown(rg, 'Items', {'(无图)'}, ...
        'Value', '(无图)', ...
        'ValueChangedFcn', @(s, e) cb.showFigure());
    h.FigureDrop.Layout.Row = 1;
    h.FigureDrop.Layout.Column = 1;

    h.OpenReportInline = uibutton(rg, 'Text', '浏览器打开', ...
        'ButtonPushedFcn', @(s, e) cb.onOpenReport());
    h.OpenReportInline.Layout.Row = 1;
    h.OpenReportInline.Layout.Column = 2;

    h.FigureImage = uiimage(rg, 'ScaleMethod', 'fit', 'Visible', 'off');
    h.FigureImage.Layout.Row = 2;
    h.FigureImage.Layout.Column = [1 2];

    t2 = uitab(tg, 'Title', '工作区');
    wg = uigridlayout(t2, [1 1]);
    wg.Padding = [8 8 8 8];
    h.WorkspaceTable = uitable(wg, ...
        'ColumnName', {'变量', '类型', '大小', '最小值', '最大值', '预览'}, ...
        'ColumnWidth', {100, 80, 75, 75, 75, '1x'}, ...
        'ColumnEditable', false, 'RowName', []);

    t3 = uitab(tg, 'Title', '绘图');
    pg = uigridlayout(t3, [5 3]);
    pg.RowHeight = {30, 82, 32, 22, '1x'};
    pg.ColumnWidth = {72, '1x', '1x'};
    pg.Padding = [8 8 8 8];
    pg.RowSpacing = 6;

    uilabel(pg, 'Text', 'X 轴');
    h.XDrop = uidropdown(pg, 'Items', {'(无)'}, 'Value', '(无)');
    h.XDrop.Layout.Row = 1;
    h.XDrop.Layout.Column = [2 3];

    uilabel(pg, 'Text', 'Y 轴（可多选）');
    h.YList = uilistbox(pg, 'Items', {'(无)'}, 'Value', {'(无)'}, ...
        'Multiselect', 'on');
    h.YList.Layout.Row = 2;
    h.YList.Layout.Column = [2 3];

    h.PlotButton = uibutton(pg, 'Text', '绘制', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onPlot());
    h.PlotButton.Layout.Row = 3;
    h.PlotButton.Layout.Column = 1;

    h.SavePlotButton = uibutton(pg, 'Text', '保存图并更新报告', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onSavePlot());
    h.SavePlotButton.Layout.Row = 3;
    h.SavePlotButton.Layout.Column = 2;

    h.ExportCsvButton = uibutton(pg, 'Text', '导出曲线 CSV', ...
        'Enable', 'off', 'ButtonPushedFcn', @(s, e) cb.onExportCurve());
    h.ExportCsvButton.Layout.Row = 3;
    h.ExportCsvButton.Layout.Column = 3;

    h.PlotStatus = uilabel(pg, 'Text', '运行脚本后，可选择工作区变量绘图。', ...
        'FontColor', [0.4 0.4 0.4]);
    h.PlotStatus.Layout.Row = 4;
    h.PlotStatus.Layout.Column = [1 3];

    h.UIAxes = uiaxes(pg);
    h.UIAxes.Layout.Row = 5;
    h.UIAxes.Layout.Column = [1 3];
    h.UIAxes.XGrid = 'on';
    h.UIAxes.YGrid = 'on';
    h.UIAxes.Box = 'on';
    h.UIAxes.FontSize = 10;
    title(h.UIAxes, '运行后在这里绘图');

    t4 = uitab(tg, 'Title', '日志');
    lg2 = uigridlayout(t4, [1 1]);
    lg2.Padding = [8 8 8 8];
    h.LogArea = uitextarea(lg2, 'Editable', 'off', ...
        'FontName', 'Consolas', 'FontSize', 11, 'Value', {''});

    h.StatusLabel = uilabel(root, ...
        'Text', '就绪。第 1 步：点左上角“打开 .m 文件”。', ...
        'FontColor', [0.35 0.35 0.35]);
    h.StatusLabel.Layout.Row = 3;

    setTooltips(h);
end

% -------------------------------------------------------------------------
function setTooltips(h)
    set(h.OpenButton, 'Tooltip', '打开一个 .m 脚本开始调参');
    set(h.RescanButton, 'Tooltip', ...
        '重新扫描当前文件；会丢弃还没运行的新值');
    set(h.RunButton, 'Tooltip', ...
        '用勾选/改好的参数运行脚本（快捷键 F5 或 Ctrl+Enter）');
    set(h.SaveButton, 'Tooltip', ...
        '另存为 <原名>_tuned.m，可以脱离本工具直接在 MATLAB 里运行');
    set(h.ReportButton, 'Tooltip', ...
        '用浏览器打开本次运行的 HTML 报告（参数+图+变量+日志）');
    set(h.FolderButton, 'Tooltip', ...
        '打开结果文件夹，里面有图、workspace.mat 和报告');
    set(h.ExportButton, 'Tooltip', ...
        '把当前识别出的所有参数导出成 JSON 文件');
    set(h.CloseFiguresButton, 'Tooltip', ...
        '关掉本次运行留在屏幕上的图窗');
    set(h.CompareButton, 'Tooltip', ...
        '查看历史运行，任意两次做对比，或载入某次的参数');
    set(h.BulkButton, 'Tooltip', ...
        '对多选行批量设值、乘系数、勾选、锁定，或从 Excel 粘贴一列');
    set(h.HelpButton, 'Tooltip', '30 秒看懂：从打开文件到保存结果');

    set(h.FilterDrop, 'Tooltip', ...
        '选择显示哪些参数：推荐参数 / 全部数字 / 已修改');
    set(h.SearchField, 'Tooltip', '按参数名、注释或行号搜索');
    set(h.SelectAllButton, 'Tooltip', ...
        '一键勾选或取消所有推荐参数');
    set(h.ResetButton, 'Tooltip', ...
        '把所有“新值”恢复成脚本里的当前值');
    set(h.AnnotateTemplateButton, 'Tooltip', ...
        '生成注释模板 JSON，交给 AI 填写参数含义和单位');
    set(h.ImportAnnotationButton, 'Tooltip', ...
        '导入 AI 填好的注释 JSON，“注释”列会显示中文含义');
    set(h.ClearAnnotationButton, 'Tooltip', ...
        '清除当前表格里的注释（注释文件不会被删除）');
    set(h.LockButton, 'Tooltip', ...
        '把选中行的参数钉死在原值，运行和保存都不会改它');
    set(h.UndoButton, 'Tooltip', '撤销上一次参数修改（Ctrl+Z）');
    set(h.RedoButton, 'Tooltip', '重做刚撤销的修改（Ctrl+Y）');
    set(h.KeepFiguresCheck, 'Tooltip', ...
        '勾选：运行结束后保留图窗；不勾选：图窗自动关闭（推荐）');
    set(h.BackgroundCheck, 'Tooltip', ...
        '在并行池后台运行单次仿真，界面不阻塞（需要 Parallel Computing Toolbox）');
    set(h.PresetDrop, 'Tooltip', '已保存的参数方案');
    set(h.PresetNameField, 'Tooltip', ...
        '给当前方案起个名字，例如 基线 / 高刚度 / 低阻尼');
    set(h.PresetSaveButton, 'Tooltip', ...
        '把当前的勾选、新值、锁定状态存成一个命名方案');
    set(h.PresetLoadButton, 'Tooltip', ...
        '把选中方案的新值、勾选、锁定恢复到表格');
    set(h.PresetDeleteButton, 'Tooltip', '删除选中的参数方案');
    set(h.SweepButton, 'Tooltip', ...
        '多个参数一次跑多组值，自动出叠加曲线和扫描报告');
    set(h.ManualButton, 'Tooltip', ...
        '添加手动参数；选中已有的手动参数可编辑（写入 _manual.json）');
    set(h.EntryButton, 'Tooltip', ...
        '为配置/函数文件选择项目入口脚本，调参后在临时项目副本中运行入口');

    set(h.FigureDrop, 'Tooltip', '选择要预览的输出图');
    set(h.OpenReportInline, 'Tooltip', '用浏览器打开 HTML 报告');
    set(h.XDrop, 'Tooltip', '绘图时的 X 轴变量');
    set(h.YList, 'Tooltip', '绘图时的 Y 轴变量，可以多选');
    set(h.PlotButton, 'Tooltip', '按选择的 X/Y 变量画图');
    set(h.SavePlotButton, 'Tooltip', ...
        '保存这张图，并把报告更新为包含它');
    set(h.ExportCsvButton, 'Tooltip', ...
        '把当前 X/Y 曲线导出成 curve_data.csv（Excel 可直接打开）');
end
