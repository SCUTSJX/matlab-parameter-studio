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
                noPresets = mps.tr('(无参数集)', '(No presets)');
                obj.PresetDrop.Items = {noPresets};
                obj.PresetDrop.Value = noPresets;
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
                error('mps:App:noFile', mps.tr( ...
                    '请先打开一个 .m 文件。', 'Open a .m file first.'));
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
                msg = mps.tr('找不到参数集：%s', ...
                    'Preset not found: %s', name);
                error('mps:App:presetNotFound', '%s', msg);
            end
            obj.UndoFcn();
            [params, stats] = mps.applyPreset(obj.App.Params, ...
                obj.Presets(idx));
            obj.App.Params = params;
            obj.RefreshFcn();
        end

        function onSave(obj)
            if isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, ...
                    mps.tr('请先打开一个 .m 文件。', ...
                    'Open a .m file first.'), ...
                    mps.tr('没有文件', 'No file'), 'Icon', 'warning');
                return;
            end
            name = strtrim(char(obj.PresetNameField.Value));
            if isempty(name) && ~isempty(obj.Presets)
                if ~strcmp(obj.PresetDrop.Value, ...
                        mps.tr('(无参数集)', '(No presets)'))
                    name = obj.PresetDrop.Value;
                end
            end
            if isempty(name)
                uialert(obj.App.UIFigure, mps.tr( ...
                    ['请输入参数集名称，或在下拉框里选择一个已有参数集' ...
                     '覆盖保存。'], ...
                    ['Enter a preset name, or select an existing preset ' ...
                     'in the dropdown to overwrite.']), ...
                    mps.tr('缺少名称', 'Missing name'), ...
                    'Icon', 'warning');
                return;
            end
            exists = any(strcmp({obj.Presets.name}, name));
            if exists
                overwriteOption = mps.tr('覆盖', 'Overwrite');
                cancelOption = mps.tr('取消', 'Cancel');
                choice = uiconfirm(obj.App.UIFigure, mps.tr( ...
                    '参数集“%s”已存在，是否覆盖？', ...
                    'Preset "%s" already exists. Overwrite it?', name), ...
                    mps.tr('覆盖参数集', 'Overwrite preset'), ...
                    'Options', {overwriteOption, cancelOption}, ...
                    'DefaultOption', 2, 'CancelOption', 2);
                if ~strcmp(choice, overwriteOption)
                    return;
                end
            end
            try
                obj.Presets = mps.savePreset(obj.App.SourceFile, name, ...
                    obj.App.Params);
            catch err
                uialert(obj.App.UIFigure, err.message, ...
                    mps.tr('保存失败', 'Save failed'), ...
                    'Icon', 'error');
                return;
            end
            obj.PresetNameField.Value = '';
            obj.refresh();
            obj.PresetDrop.Value = name;
            obj.StatusLabel.Text = mps.tr('已保存参数集：%s（%s）', ...
                'Preset saved: %s (%s)', name, obj.PresetsFile);
        end

        function onLoad(obj)
            if isempty(obj.Presets) || isempty(obj.App.SourceFile)
                uialert(obj.App.UIFigure, ...
                    mps.tr('还没有可载入的参数集。', ...
                    'There are no presets to load.'), ...
                    mps.tr('没有参数集', 'No presets'), ...
                    'Icon', 'warning');
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
                uialert(obj.App.UIFigure, err.message, ...
                    mps.tr('载入失败', 'Load failed'), ...
                    'Icon', 'error');
                return;
            end
            obj.RefreshFcn();
            obj.StatusLabel.Text = mps.tr( ...
                ['已载入参数集：%s（匹配 %d，重名跳过 %d，未匹配 %d，' ...
                 '无效值 %d）'], ...
                ['Preset loaded: %s (%d matched, %d ambiguous, ' ...
                 '%d unmatched, %d invalid)'], ...
                name, stats.matched, stats.ambiguous, stats.unmatched, ...
                stats.invalid);
            if stats.unmatched > 0 || stats.ambiguous > 0 || stats.invalid > 0
                uialert(obj.App.UIFigure, mps.tr( ...
                    ['载入“%s”：匹配 %d，重名跳过 %d，未匹配 %d，' ...
                     '无效值 %d。\n\n' ...
                     '未匹配通常是因为脚本改过变量名或行号；参数集里的 id ' ...
                     '保留的是保存时的位置。无效值不是数值表达式，' ...
                     '已按原值跳过。'], ...
                    ['Loaded "%s": %d matched, %d ambiguous, ' ...
                     '%d unmatched, %d invalid.\n\n' ...
                     'Unmatched entries usually mean variable names or ' ...
                     'line numbers changed in the script; the preset id ' ...
                     'records the position at save time. Invalid values ' ...
                     'are not numeric expressions and were skipped.'], ...
                    name, stats.matched, stats.ambiguous, ...
                    stats.unmatched, stats.invalid), ...
                    mps.tr('载入参数集', 'Load preset'), ...
                    'Icon', 'warning');
            end
        end

        function onDelete(obj)
            if isempty(obj.Presets)
                return;
            end
            name = obj.PresetDrop.Value;
            deleteOption = mps.tr('删除', 'Delete');
            cancelOption = mps.tr('取消', 'Cancel');
            choice = uiconfirm(obj.App.UIFigure, mps.tr( ...
                '删除参数集“%s”？', 'Delete preset "%s"?', name), ...
                mps.tr('删除参数集', 'Delete preset'), ...
                'Options', {deleteOption, cancelOption}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(choice, deleteOption)
                return;
            end
            keep = ~strcmp({obj.Presets.name}, name);
            try
                % Write to disk first; only then update memory, so a failed
                % write leaves the dropdown and the JSON file consistent.
                mps.writePresets(obj.App.SourceFile, obj.Presets(keep));
            catch err
                uialert(obj.App.UIFigure, err.message, ...
                    mps.tr('删除失败', 'Delete failed'), ...
                    'Icon', 'error');
                return;
            end
            obj.Presets = obj.Presets(keep);
            obj.refresh();
            obj.StatusLabel.Text = mps.tr('已删除参数集：%s', ...
                'Preset deleted: %s', name);
        end
    end
end
