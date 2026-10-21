classdef ParameterTableController < handle
%PARAMETERTABLECONTROLLER Own the parameter table, selection, undo and session.
%
%   The controller holds Params / SelectedParams / annotations and drives
%   the table, filter, source preview and undo buttons.  App exposes its own
%   Params/SelectedParams as dependent aliases, so the rest of the app can
%   keep using app.Params.

    properties
        Params = struct([])
        SelectedParams = []
        LastAnnotations = struct([])
        AnnotationFile = ''
        SourceLines = {}
        RecommendedMinScore = 3
    end

    properties (Access = private)
        SourceLinesByFile
    end

    properties (Access = private)
        SourceFile = ''
        SourceStamp = struct()
        VisibleIdx = []
        UndoStack = {}
        RedoStack = {}
        MaxUndo = 50
        RestoringState = false
        SessionDirty = false
        Busy = false
        UIFigure
        Table
        FilterDrop
        SearchField
        FileFilterDrop
        CountLabel
        SelectAllButton
        SourcePreview
        LockButton
        UndoButton
        RedoButton
        AnnotationStatus
        StatusLabel
    end

    methods
        function obj = ParameterTableController(uiFigure, table, filterDrop, ...
                searchField, fileFilterDrop, countLabel, selectAllButton, ...
                sourcePreview, lockButton, undoButton, redoButton, ...
                annotationStatus, statusLabel)
            obj.SourceLinesByFile = containers.Map( ...
                'KeyType', 'char', 'ValueType', 'any');
            obj.UIFigure = uiFigure;
            obj.Table = table;
            obj.FilterDrop = filterDrop;
            obj.SearchField = searchField;
            obj.FileFilterDrop = fileFilterDrop;
            obj.CountLabel = countLabel;
            obj.SelectAllButton = selectAllButton;
            obj.SourcePreview = sourcePreview;
            obj.LockButton = lockButton;
            obj.UndoButton = undoButton;
            obj.RedoButton = redoButton;
            obj.AnnotationStatus = annotationStatus;
            obj.StatusLabel = statusLabel;
        end

        function setSource(obj, sourceFile, stamp)
            obj.SourceFile = char(sourceFile);
            obj.SourceStamp = stamp;
            obj.SourceLinesByFile = containers.Map( ...
                'KeyType', 'char', 'ValueType', 'any');
        end

        function resetHistory(obj)
            obj.UndoStack = {};
            obj.RedoStack = {};
            obj.SessionDirty = false;
            obj.RestoringState = false;
            obj.updateUndoButtons();
        end

        function clearSelection(obj)
            obj.SelectedParams = [];
        end

        function tf = needsSave(obj)
            tf = obj.SessionDirty;
        end

        function markDirty(obj)
            obj.SessionDirty = true;
        end

        function saveSession(obj)
            if isempty(obj.SourceFile) || isempty(obj.Params)
                return;
            end
            try
                mps.writeSession(obj.SourceFile, obj.Params, obj.SourceStamp);
                mps.writeManualParams(obj.SourceFile, obj.Params);
                obj.SessionDirty = false;
            catch err
                mps.logWarning('保存会话和手动参数', err);
            end
        end

        function setBusy(obj, busy)
            obj.Busy = logical(busy);
            obj.updateUndoButtons();
        end

        function pushUndo(obj)
            if obj.RestoringState
                return;
            end
            obj.UndoStack{end+1} = obj.snapshotState();
            if numel(obj.UndoStack) > obj.MaxUndo
                obj.UndoStack(1) = [];
            end
            obj.RedoStack = {};
            obj.SessionDirty = true;
            obj.updateUndoButtons();
        end

        function undo(obj)
            if isempty(obj.UndoStack)
                return;
            end
            obj.RedoStack{end+1} = obj.snapshotState();
            state = obj.UndoStack{end};
            obj.UndoStack(end) = [];
            obj.RestoringState = true;
            obj.restoreState(state);
            obj.RestoringState = false;
            obj.SessionDirty = true;
            obj.refresh();
            obj.StatusLabel.Text = mps.tr('已撤销上一次修改。', ...
                'Undid the last change.');
        end

        function redo(obj)
            if isempty(obj.RedoStack)
                return;
            end
            obj.UndoStack{end+1} = obj.snapshotState();
            state = obj.RedoStack{end};
            obj.RedoStack(end) = [];
            obj.RestoringState = true;
            obj.restoreState(state);
            obj.RestoringState = false;
            obj.SessionDirty = true;
            obj.refresh();
            obj.StatusLabel.Text = mps.tr('已重做上一次修改。', ...
                'Redid the last change.');
        end

        function refresh(obj)
            allFiles = mps.tr('(全部文件)', '(All files)');
            if isempty(obj.Params)
                obj.Table.Data = cell(0, 10);
                obj.VisibleIdx = [];
                obj.clearSelection();
                obj.FileFilterDrop.Items = {allFiles};
                obj.FileFilterDrop.Value = allFiles;
                obj.CountLabel.Text = '0 / 0';
                obj.updateAnnotationStatus();
                obj.updateUndoButtons();
                return;
            end

            files = unique({obj.Params.sourceFile});
            labels = unique(cellfun(@fileName, files, ...
                'UniformOutput', false), 'stable');
            obj.FileFilterDrop.Items = [{allFiles}, labels]; %#ok<AGROW>
            if ~any(strcmp(obj.FileFilterDrop.Items, obj.FileFilterDrop.Value))
                obj.FileFilterDrop.Value = obj.FileFilterDrop.Items{1};
            end
            fileFilter = char(obj.FileFilterDrop.Value);

            for k = 1:numel(obj.Params)
                obj.Params(k).isChanged = ~strcmp( ...
                    strtrim(obj.Params(k).value), ...
                    strtrim(obj.Params(k).newValue));
            end

            mode = obj.FilterDrop.Value;
            recommended = mps.tr('推荐参数', 'Recommended');
            modified = mps.tr('已修改', 'Modified');
            q = lower(strtrim(char(obj.SearchField.Value)));
            idx = [];
            for k = 1:numel(obj.Params)
                p = obj.Params(k);
                switch mode
                    case recommended
                        keep = p.score >= obj.RecommendedMinScore;
                    case modified
                        keep = p.isChanged;
                    otherwise
                        keep = true;
                end
                if keep && ~strcmp(fileFilter, allFiles) && ...
                        ~strcmp(fileName(p.sourceFile), fileFilter)
                    keep = false;
                end
                if keep && ~isempty(q)
                    hay = lower(sprintf('%s %s %s %s %s %s %d', ...
                        p.name, p.description, p.unit, p.note, ...
                        p.context, fileName(p.sourceFile), p.line));
                    keep = contains(hay, q);
                end
                if keep
                    idx(end+1) = k; %#ok<AGROW>
                end
            end
            obj.VisibleIdx = idx;

            data = cell(numel(idx), 10);
            for j = 1:numel(idx)
                p = obj.Params(idx(j));
                note = p.note;
                if isempty(note)
                    note = p.context;
                end
                if numel(note) > 120
                    note = [note(1:117), '...'];
                end
                if p.locked
                    nameCell = ['[' mps.tr('锁', 'Lock') '] ' p.name];
                else
                    nameCell = p.name;
                end
                data{j,1} = p.use;
                data{j,2} = p.locked;
                data{j,3} = fileName(p.sourceFile);
                data{j,4} = nameCell;
                data{j,5} = p.value;
                data{j,6} = p.newValue;
                data{j,7} = p.line;
                data{j,8} = categoryLabel(p.category);
                data{j,9} = note;
                data{j,10} = annotationText(p);
            end
            obj.Table.Data = data;
            obj.restoreTableSelection();
            obj.CountLabel.Text = mps.tr('%d / %d · 已修改 %d', ...
                '%d / %d · %d modified', numel(idx), ...
                numel(obj.Params), sum([obj.Params.isChanged]));
            obj.updateAnnotationStatus();

            rec = [obj.Params.score] >= obj.RecommendedMinScore;
            if any(rec)
                if all([obj.Params(rec).use])
                    obj.SelectAllButton.Text = mps.tr('取消全选', ...
                        'Deselect all');
                else
                    obj.SelectAllButton.Text = mps.tr('全选推荐', ...
                        'Use recommended');
                end
            end
            obj.updateUndoButtons();
            if obj.SessionDirty
                obj.saveSession();
            end
        end

        function onCellEdit(obj, event)
            if isempty(event.Indices) || isempty(obj.VisibleIdx)
                return;
            end
            row = event.Indices(1);
            col = event.Indices(2);
            if row < 1 || row > numel(obj.VisibleIdx)
                return;
            end
            idx = obj.VisibleIdx(row);
            if col == 1
                obj.pushUndo();
                obj.Params(idx).use = logical(event.NewData);
            elseif col == 2
                obj.pushUndo();
                lock = logical(event.NewData);
                obj.Params(idx).locked = lock;
                if lock
                    obj.Params(idx).newValue = obj.Params(idx).value;
                    obj.Params(idx).isChanged = false;
                end
            elseif col == 6
                if obj.Params(idx).locked
                    obj.alert(mps.tr( ...
                        '该参数已锁定，不能修改。请先在“锁定”列取消勾选。', ...
                        ['This parameter is locked and cannot be changed. ' ...
                         'Clear the "Lock" column first.']), ...
                        mps.tr('参数已锁定', 'Parameter locked'), ...
                        'Icon', 'warning');
                    obj.refresh();
                    return;
                end
                newVal = strtrim(char(event.NewData));
                if isempty(newVal)
                    newVal = obj.Params(idx).value;
                end
                [ok, ~] = mps.validateValue(newVal);
                if ~ok
                    obj.alert(mps.tr( ...
                        '“%s”不是有效的数值表达式。\n\n示例：2、2*pi、[1 2 3]、1:0.1:10', ...
                        ['"%s" is not a valid numeric expression.' ...
                         '\n\nExamples: 2, 2*pi, [1 2 3], 1:0.1:10'], ...
                        newVal), mps.tr('输入无效', 'Invalid input'), ...
                        'Icon', 'warning');
                    obj.refresh();
                    return;
                end
                obj.pushUndo();
                obj.Params(idx).newValue = newVal;
                obj.Params(idx).isChanged = ~strcmp( ...
                    strtrim(obj.Params(idx).value), newVal);
            end
            obj.refresh();
        end

        function onCellSelect(obj, event)
            if isempty(event.Indices) || isempty(obj.VisibleIdx)
                obj.clearSelection();
                obj.SourcePreview.Value = {''};
                obj.updateLockButton();
                return;
            end
            rows = [];
            try
                selection = obj.Table.Selection;
                if ~isempty(selection)
                    rows = unique(selection(:, 1));
                end
            catch err
                mps.logWarning('读取参数表选中行', err, 'Silent', true);
            end
            if isempty(rows)
                rows = unique(event.Indices(:, 1));
            end
            rows = rows(rows >= 1 & rows <= numel(obj.VisibleIdx));
            if isempty(rows)
                obj.clearSelection();
                obj.SourcePreview.Value = {''};
                obj.updateLockButton();
                return;
            end
            obj.SelectedParams = obj.VisibleIdx(rows);
            obj.updateLockButton();

            row = rows(end);
            idx = obj.VisibleIdx(row);
            lines = obj.linesFor(obj.Params(idx).sourceFile);
            if isempty(lines)
                obj.SourcePreview.Value = {''};
                return;
            end
            lineNo = obj.Params(idx).line;
            % The parameter table is a snapshot; the file may have shrunk
            % since the scan, so clamp the line into the current range.
            lineNo = min(max(lineNo, 1), numel(lines));
            lo = max(1, lineNo - 2);
            hi = min(numel(lines), lineNo + 2);
            preview = cell(hi - lo + 1, 1);
            for j = lo:hi
                if j == lineNo
                    marker = '>> ';
                else
                    marker = '   ';
                end
                preview{j - lo + 1} = sprintf('%s%4d | %s', ...
                    marker, j, lines{j});
            end
            ann = annotationText(obj.Params(idx));
            if ~isempty(ann)
                preview = [{[mps.tr('注释：', 'Notes: ') ann]}; ...
                    {''}; preview];
            end
            obj.SourcePreview.Value = preview;
        end

        function onSelectAll(obj)
            if isempty(obj.Params)
                return;
            end
            rec = [obj.Params.score] >= obj.RecommendedMinScore;
            if ~any(rec)
                return;
            end
            obj.pushUndo();
            if all([obj.Params(rec).use])
                for k = find(rec)
                    obj.Params(k).use = false;
                end
            else
                for k = find(rec)
                    obj.Params(k).use = true;
                end
            end
            obj.refresh();
        end

        function onReset(obj)
            obj.pushUndo();
            for k = 1:numel(obj.Params)
                obj.Params(k).newValue = obj.Params(k).value;
                obj.Params(k).isChanged = false;
            end
            obj.refresh();
            obj.StatusLabel.Text = mps.tr( ...
                '已把所有新值重置为当前值。', ...
                'Reset all new values to their current values.');
        end

        function onBulkEdit(obj)
            if isempty(obj.SourceFile)
                obj.alert(mps.tr('请先打开一个 .m 文件。', ...
                    'Open a .m file first.'), ...
                    mps.tr('没有文件', 'No file'), 'Icon', 'warning');
                return;
            end
            if isempty(obj.Params)
                return;
            end
            paramsSnapshot = obj.Params;
            dlg = mps.BulkEditDialog(obj.Params, obj.SelectedParams, ...
                obj.VisibleIdx);
            uiwait(dlg.UIFigure);
            result = dlg.Result;
            delete(dlg);
            if ~isstruct(result) || ~isfield(result, 'op')
                return;
            end
            % The dialog is non-modal: undo, presets or another file may
            % have replaced the table while it was open.  Indices computed
            % from the old snapshot would silently edit wrong parameters.
            if ~isequal(obj.Params, paramsSnapshot)
                obj.alert(mps.tr( ...
                    ['对话框打开期间参数表已发生变化，' ...
                     '本次批量修改已取消，请重新操作。'], ...
                    ['The parameter table changed while the dialog was ' ...
                     'open, so this bulk edit was cancelled. ' ...
                     'Please try again.']), ...
                    mps.tr('参数已变化', 'Parameters changed'), ...
                    'Icon', 'warning');
                return;
            end

            obj.pushUndo();
            try
                if strcmp(result.op, 'paste')
                    [obj.Params, stats] = mps.applyPastedValues( ...
                        obj.Params, result.indices, result.values);
                else
                    [obj.Params, stats] = mps.bulkEdit( ...
                        obj.Params, result.indices, result.op, result.value);
                end
            catch err
                obj.alert(err.message, ...
                    mps.tr('批量修改失败', 'Bulk edit failed'), ...
                    'Icon', 'error');
                return;
            end

            obj.refresh();
            msg = mps.tr('批量修改：%d 个参数已更新', ...
                'Bulk edit: %d parameters updated', stats.changed);
            if stats.skippedLocked > 0
                msg = mps.tr('%s，跳过已锁定 %d 个', ...
                    '%s, %d locked skipped', msg, stats.skippedLocked);
            end
            if stats.skippedNonNumeric > 0
                msg = mps.tr('%s，跳过非数值 %d 个', ...
                    '%s, %d non-numeric skipped', msg, ...
                    stats.skippedNonNumeric);
            end
            if stats.skippedInvalid > 0
                msg = mps.tr('%s，跳过无效 %d 个', ...
                    '%s, %d invalid skipped', msg, stats.skippedInvalid);
            end
            obj.StatusLabel.Text = [msg mps.tr('。', '.')];
        end

        function setParam(obj, name, value)
            if isnumeric(value) || islogical(value)
                value = num2str(value);
            end
            value = char(value);
            matches = find(strcmp({obj.Params.name}, name));
            if isempty(matches)
                return;
            end
            obj.pushUndo();
            for k = matches
                if obj.Params(k).locked
                    continue;
                end
                obj.Params(k).newValue = value;
                obj.Params(k).isChanged = ~strcmp( ...
                    strtrim(obj.Params(k).value), strtrim(value));
                obj.Params(k).use = true;
            end
            obj.refresh();
        end

        function toggleLock(obj, name)
            obj.pushUndo();
            for k = 1:numel(obj.Params)
                if strcmp(obj.Params(k).name, name)
                    obj.Params(k).locked = ~obj.Params(k).locked;
                    if obj.Params(k).locked
                        obj.Params(k).newValue = obj.Params(k).value;
                        obj.Params(k).isChanged = false;
                    end
                end
            end
            obj.refresh();
        end

        function onToggleLock(obj)
            indices = obj.SelectedParams;
            if isempty(indices)
                obj.alert(mps.tr( ...
                    '请先在参数表里点选一行（可多选）。', ...
                    ['Select a row in the parameter table first ' ...
                     '(multi-select is supported).']), ...
                    mps.tr('没有选中行', 'No row selected'), ...
                    'Icon', 'warning');
                return;
            end
            obj.pushUndo();
            if all([obj.Params(indices).locked])
                for idx = indices
                    obj.Params(idx).locked = false;
                    obj.Params(idx).isChanged = ~strcmp( ...
                        strtrim(obj.Params(idx).value), ...
                        strtrim(obj.Params(idx).newValue));
                end
                obj.StatusLabel.Text = mps.tr( ...
                    '已解锁 %d 个参数。', 'Unlocked %d parameters.', ...
                    numel(indices));
            else
                for idx = indices
                    obj.Params(idx).locked = true;
                    obj.Params(idx).newValue = obj.Params(idx).value;
                    obj.Params(idx).isChanged = false;
                end
                obj.StatusLabel.Text = mps.tr( ...
                    '已锁定 %d 个参数（新值保持原值）。', ...
                    ['Locked %d parameters (new values keep the ' ...
                     'current values).'], numel(indices));
            end
            obj.refresh();
        end
    end

    methods (Access = private)
        function state = snapshotState(obj)
            state = {obj.Params, obj.SelectedParams, ...
                obj.LastAnnotations, obj.AnnotationFile};
        end

        function restoreState(obj, state)
            obj.Params = state{1};
            obj.SelectedParams = state{2};
            obj.LastAnnotations = state{3};
            obj.AnnotationFile = state{4};
        end

        function lines = linesFor(obj, file)
            file = char(file);
            if strcmp(file, obj.SourceFile) && ~isempty(obj.SourceLines)
                lines = obj.SourceLines;
                return;
            end
            if isKey(obj.SourceLinesByFile, file)
                lines = obj.SourceLinesByFile(file);
                return;
            end
            lines = {};
            try
                raw = fileread(file);
                raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
                raw = strrep(raw, sprintf('\r'), sprintf('\n'));
                lines = regexp(raw, '\n', 'split');
                if ~isempty(lines) && isempty(lines{end})
                    lines(end) = [];
                end
                obj.SourceLinesByFile(file) = lines;
            catch err
                mps.logWarning(sprintf('读取源码预览 %s', file), err);
            end
        end

        function restoreTableSelection(obj)
            if ~isempty(obj.SelectedParams)
                [keep, visibleRows] = ismember(obj.SelectedParams, ...
                    obj.VisibleIdx);
                obj.SelectedParams = obj.SelectedParams(keep);
                visibleRows = visibleRows(keep);
            else
                visibleRows = [];
            end
            try
                if isempty(visibleRows)
                    obj.Table.Selection = [];
                else
                    obj.Table.Selection = [visibleRows(:), ...
                        ones(numel(visibleRows), 1)];
                end
            catch err
                mps.logWarning('恢复参数表选中行', err, 'Silent', true);
            end
            obj.updateLockButton();
        end

        function updateLockButton(obj)
            indices = obj.SelectedParams;
            if isempty(indices)
                obj.LockButton.Text = mps.tr('锁定选中', 'Lock selected');
                return;
            end
            if all([obj.Params(indices).locked])
                obj.LockButton.Text = mps.tr('解锁选中 (%d)', ...
                    'Unlock selected (%d)', numel(indices));
            else
                obj.LockButton.Text = mps.tr('锁定选中 (%d)', ...
                    'Lock selected (%d)', numel(indices));
            end
        end

        function updateAnnotationStatus(obj)
            total = numel(obj.Params);
            n = 0;
            for k = 1:total
                if ~isempty(obj.Params(k).description) || ...
                        ~isempty(obj.Params(k).unit)
                    n = n + 1;
                end
            end
            if n == 0
                obj.AnnotationStatus.Text = mps.tr('未导入注释', ...
                    'None');
                obj.AnnotationStatus.FontColor = [0.4 0.4 0.4];
            else
                obj.AnnotationStatus.Text = mps.tr('已注释 %d / %d', ...
                    'Notes %d/%d', n, total);
                obj.AnnotationStatus.FontColor = [0.05 0.45 0.15];
            end
        end

        function updateUndoButtons(obj)
            if isempty(obj.UndoButton) || ~isvalid(obj.UndoButton)
                return;
            end
            if obj.Busy
                obj.UndoButton.Enable = 'off';
                obj.RedoButton.Enable = 'off';
                return;
            end
            if isempty(obj.UndoStack)
                obj.UndoButton.Enable = 'off';
            else
                obj.UndoButton.Enable = 'on';
            end
            if isempty(obj.RedoStack)
                obj.RedoButton.Enable = 'off';
            else
                obj.RedoButton.Enable = 'on';
            end
        end

        function alert(obj, message, title, varargin)
            if strcmp(obj.UIFigure.Visible, 'on')
                uialert(obj.UIFigure, message, title, varargin{:});
            else
                obj.StatusLabel.Text = char(message);
            end
        end
    end
end

% -------------------------------------------------------------------------
function name = fileName(path)
    [~, base, ext] = fileparts(char(path));
    name = [base ext];
    if isempty(name)
        name = '(unknown)';
    end
end

% -------------------------------------------------------------------------
function s = annotationText(p)
    s = '';
    if isfield(p, 'description')
        s = p.description;
    end
    if isfield(p, 'unit') && ~isempty(p.unit)
        if isempty(s)
            s = ['[' p.unit ']'];
        else
            s = sprintf('%s (%s)', s, p.unit);
        end
    end
    if numel(s) > 200
        s = [s(1:197), '...'];
    end
end

% -------------------------------------------------------------------------
function s = categoryLabel(c)
    switch c
        case 'assignment', s = mps.tr('赋值', 'Assignment');
        case 'struct', s = mps.tr('结构体字段', 'Struct field');
        case 'array', s = mps.tr('数组元素', 'Array element');
        case 'range', s = mps.tr('范围', 'Range');
        case 'expression', s = mps.tr('表达式', 'Expression');
        case 'argument', s = mps.tr('函数参数', 'Function argument');
        case 'index', s = mps.tr('索引', 'Index');
        case 'style', s = mps.tr('绘图样式', 'Plot style');
        case 'layout', s = mps.tr('界面布局', 'UI layout');
        case 'size', s = mps.tr('数组尺寸', 'Array size');
        case 'control', s = mps.tr('控制流', 'Control flow');
        case 'function', s = mps.tr('函数体', 'Function body');
        case 'annotated', s = mps.tr('注释标记', 'Annotation marker');
        case 'ignored', s = mps.tr('已忽略', 'Ignored');
        case 'manual', s = mps.tr('手动参数', 'Manual parameter');
        otherwise, s = c;
    end
end
