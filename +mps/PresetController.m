classdef PresetController < handle
    %PRESETCONTROLLER Manage named parameter presets for one source file.
    %
    %   The controller owns the preset list and drives the preset combo box,
    %   name field and buttons.  App keeps the public commands
    %   saveCurrentPreset / listPresets / applyPresetByName as thin aliases.

    properties
        App
        Presets = struct([])
        PresetsFile = ''
        PresetDrop
        PresetNameField
        PresetSaveButton
        PresetLoadButton
        PresetDeleteButton
        StatusLabel
        UndoFcn = @() []
        RefreshFcn = @() []
    end

    methods
        function obj = PresetController(app, presetDrop, nameField, ...
                saveButton, loadButton, deleteButton, statusLabel)
            obj.App = app;
            obj.PresetDrop = presetDrop;
            obj.PresetNameField = nameField;
            obj.PresetSaveButton = saveButton;
            obj.PresetLoadButton = loadButton;
            obj.PresetDeleteButton = deleteButton;
            obj.StatusLabel = statusLabel;
        end

        function loadFromDisk(obj)
            obj.Presets = struct([]);
            obj.PresetsFile = '';
            if ~isempty(obj.App.SourceFile)
                obj.PresetsFile = mps.presetsPath(obj.App.SourceFile);
                try
                    obj.Presets = mps.readPresets(obj.App.SourceFile);
                catch err
                    obj.Presets = struct([]);
                    mps.logWarning('读取参数集', err);
                end
            end
            obj.refresh();
        end

        function refresh(obj)
            names = {};
            if ~isempty(obj.Presets)
                names = {obj.Presets.name};
            end
            if isempty(names)
                obj.PresetDrop.Items = {'(无参数集)'};
                obj.PresetDrop.Value = '(无参数集)';
                obj.PresetLoadButton.Enable = 'off';
                obj.PresetDeleteButton.Enable = 'off';
                return;
            end
            obj.PresetDrop.Items = names;
            if ~any(strcmp(names, obj.PresetDrop.Value))
                obj.PresetDrop.Value = names{1};
            end
            if isempty(obj.App.SourceFile)
                obj.PresetLoadButton.Enable = 'off';
                obj.PresetDeleteButton.Enable = 'off';
            else
                obj.PresetLoadButton.Enable = 'on';
                obj.PresetDeleteButton.Enable = 'on';
            end
        end

        function saveCurrent(obj, name)
            if isempty(obj.App.SourceFile)
                error('mps:App:noFile', '请先打开一个 .m 文件。');
            end
            obj.Presets = mps.savePreset(obj.App.SourceFile, name, ...
                obj.App.Params);
            obj.refresh();
        end

        function names = list(obj)
            names = {};
            if ~isempty(obj.Presets)
                names = {obj.Presets.name};
            end
        end

        function stats = applyByName(obj, name)
            idx = find(strcmp({obj.Presets.name}, name), 1);
            if isempty(idx)
                error('mps:App:presetNotFound', '找不到参数集：%s', name);
            end
            obj.UndoFcn();
            [params, stats] = mps.applyPreset(obj.App.Params, ...
                obj.Presets(idx));
            obj.App.Params = params;
            obj.RefreshFcn();
        end

        function onSave(obj)
            if isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, '请先打开一个 .m 文件。', ...
                    '没有文件', 'Icon', 'warning');
                return;
            end
            name = strtrim(char(obj.PresetNameField.Value));
            if isempty(name) && ~isempty(obj.Presets)
                if ~strcmp(obj.PresetDrop.Value, '(无参数集)')
                    name = obj.PresetDrop.Value;
                end
            end
            if isempty(name)
                uialert(obj.App.UIFigure, ...
                    '请输入参数集名称，或在下拉框里选择一个已有参数集覆盖保存。', ...
                    '缺少名称', 'Icon', 'warning');
                return;
            end
            exists = any(strcmp({obj.Presets.name}, name));
            if exists
                choice = uiconfirm(obj.App.UIFigure, ...
                    sprintf('参数集“%s”已存在，是否覆盖？', name), ...
                    '覆盖参数集', 'Options', {'覆盖', '取消'}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, '覆盖')
                    return;
                end
            end
            try
                obj.Presets = mps.savePreset(obj.App.SourceFile, name, ...
                    obj.App.Params);
            catch err
                uialert(obj.App.UIFigure, err.message, '保存失败', ...
                    'Icon', 'error');
                return;
            end
            obj.PresetNameField.Value = '';
            obj.refresh();
            obj.PresetDrop.Value = name;
            obj.StatusLabel.Text = sprintf('已保存参数集：%s（%s）', ...
                name, obj.PresetsFile);
        end

        function onLoad(obj)
            if isempty(obj.Presets) || isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, '还没有可载入的参数集。', ...
                    '没有参数集', 'Icon', 'warning');
                return;
            end
            name = obj.PresetDrop.Value;
            idx = find(strcmp({obj.Presets.name}, name), 1);
            if isempty(idx)
                return;
            end
            obj.UndoFcn();
            try
                [params, stats] = mps.applyPreset(obj.App.Params, ...
                    obj.Presets(idx));
                obj.App.Params = params;
            catch err
                uialert(obj.App.UIFigure, err.message, '载入失败', ...
                    'Icon', 'error');
                return;
            end
            obj.RefreshFcn();
            obj.StatusLabel.Text = sprintf( ...
                '已载入参数集：%s（匹配 %d，重名跳过 %d，未匹配 %d）', ...
                name, stats.matched, stats.ambiguous, stats.unmatched);
            if stats.unmatched > 0 || stats.ambiguous > 0
                uialert(obj.App.UIFigure, sprintf( ...
                    ['载入“%s”：匹配 %d，重名跳过 %d，未匹配 %d。\n\n' ...
                     '未匹配通常是因为脚本改过变量名或行号；参数集里的 id ' ...
                     '保留的是保存时的位置。'], name, stats.matched, ...
                    stats.ambiguous, stats.unmatched), ...
                    '载入参数集', 'Icon', 'warning');
            end
        end

        function onDelete(obj)
            if isempty(obj.Presets)
                return;
            end
            name = obj.PresetDrop.Value;
            choice = uiconfirm(obj.App.UIFigure, ...
                sprintf('删除参数集“%s”？', name), '删除参数集', ...
                'Options', {'删除', '取消'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, '删除')
                return;
            end
            keep = ~strcmp({obj.Presets.name}, name);
            obj.Presets = obj.Presets(keep);
            try
                mps.writePresets(obj.App.SourceFile, obj.Presets);
            catch err
                uialert(obj.App.UIFigure, err.message, '删除失败', ...
                    'Icon', 'error');
                return;
            end
            obj.refresh();
            obj.StatusLabel.Text = sprintf('已删除参数集：%s', name);
        end
    end
end
