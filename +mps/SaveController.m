classdef SaveController < handle
%SAVECONTROLLER Save the tuned script / export the parameter JSON.
%
%   The app checks the source-file stamp first, then calls:
%       app.Save.saveTuned(sourceFile, params)
%       app.Save.exportParams(sourceFile, params)

    properties
        UIFigure
        StatusLabel
    end

    methods
        function obj = SaveController(uiFigure, statusLabel)
            obj.UIFigure = uiFigure;
            obj.StatusLabel = statusLabel;
        end

        function saveTuned(obj, sourceFile, params)
            if isempty(sourceFile)
                return;
            end
            [~, base] = fileparts(sourceFile);
            defaultName = fullfile(fileparts(sourceFile), [base '_tuned.m']);
            [file, path] = uiputfile( ...
                {'*.m', mps.tr('MATLAB 脚本 (*.m)', ...
                'MATLAB script (*.m)')}, ...
                mps.tr('保存调参后的脚本', 'Save tuned script'), ...
                defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            if strcmpi(target, sourceFile)
                obj.alert(mps.tr( ...
                    '不能覆盖原文件。请使用 _tuned 后缀或其他文件名。', ...
                    ['Cannot overwrite the source file. Use the _tuned ' ...
                     'suffix or another file name.']), ...
                    mps.tr('保存失败', 'Save failed'), ...
                    'Icon', 'warning');
                return;
            end

            stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            footer = sprintf('%% ---- MATLAB Parameter Studio overrides (%s) ----\n', stamp);
            footer = [footer, mps.tr('%% 源文件: %s\n', ...
                '%% Source file: %s\n', sourceFile)];
            anyChange = false;
            for k = 1:numel(params)
                p = params(k);
                if p.use && ~strcmp(strtrim(p.value), strtrim(p.newValue))
                    ann = annotationText(p);
                    if isempty(ann)
                        annSuffix = '';
                    else
                        annSuffix = ['  % ' ann];
                    end
                    footer = [footer, mps.tr( ...
                        '%%   %s = %s  (原值 %s, 第 %d 行)%s\n', ...
                        '%%   %s = %s  (was %s, line %d)%s\n', ...
                        p.name, p.newValue, p.value, p.line, annSuffix)]; %#ok<AGROW>
                    anyChange = true;
                end
            end
            if ~anyChange
                footer = [footer, sprintf(mps.tr( ...
                    '%%   本次没有修改参数。\n', ...
                    '%%   No parameters were changed this time.\n'))];
            end

            try
                original = fileread(sourceFile);
                [outText, applied] = mps.applyEdits(sourceFile, ...
                    params, '', 'Footer', footer);
            catch err
                obj.alert(err.message, ...
                    mps.tr('保存失败', 'Save failed'), 'Icon', 'error');
                return;
            end

            diffLines = mps.textDiff(original, outText);
            dlg = mps.DiffDialog(mps.tr('保存到：%s', ...
                'Save to: %s', target), diffLines);
            uiwait(dlg.UIFigure);
            confirmed = dlg.Result;
            delete(dlg);
            if ~confirmed
                obj.StatusLabel.Text = mps.tr('已取消保存。', ...
                    'Save cancelled.');
                return;
            end

            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                obj.alert(mps.tr('无法写入目标文件。', ...
                    'Cannot write the target file.'), ...
                    mps.tr('保存失败', 'Save failed'), 'Icon', 'error');
                return;
            end
            try
                fprintf(fid, '%s', outText);
            catch err
                fclose(fid);
                obj.alert(err.message, ...
                    mps.tr('保存失败', 'Save failed'), 'Icon', 'error');
                return;
            end
            fclose(fid);

            [folder, outBase] = fileparts(target);
            jsonPath = fullfile(folder, [outBase '_params.json']);
            fid = fopen(jsonPath, 'w', 'n', 'UTF-8');
            if fid >= 0
                try
                    fprintf(fid, '%s', jsonencode(applied));
                catch err
                    fclose(fid);
                    obj.alert(err.message, ...
                        mps.tr('保存失败', 'Save failed'), ...
                        'Icon', 'error');
                    return;
                end
                fclose(fid);
            end

            obj.StatusLabel.Text = mps.tr('已保存调参脚本：%s', ...
                'Tuned script saved: %s', target);
            obj.alert(mps.tr( ...
                ['已保存脚本：\n%s\n\n参数记录：\n%s\n\n' ...
                 '脚本可以直接在 MATLAB 中运行。'], ...
                ['Script saved:\n%s\n\nParameter record:\n%s\n\n' ...
                 'The script can be run directly in MATLAB.'], ...
                target, jsonPath), mps.tr('保存成功', 'Saved'), ...
                'Icon', 'info');
        end

        function exportParams(obj, sourceFile, params)
            if isempty(sourceFile)
                return;
            end
            [~, base] = fileparts(sourceFile);
            defaultName = fullfile(fileparts(sourceFile), [base '_params.json']);
            [file, path] = uiputfile( ...
                {'*.json', mps.tr('JSON 文件 (*.json)', ...
                'JSON file (*.json)')}, ...
                mps.tr('导出参数集', 'Export presets'), defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                obj.alert(mps.tr('无法写入文件。', ...
                    'Cannot write the file.'), ...
                    mps.tr('导出失败', 'Export failed'), ...
                    'Icon', 'error');
                return;
            end
            try
                fprintf(fid, '%s', jsonencode(params));
            catch err
                fclose(fid);
                obj.alert(err.message, ...
                    mps.tr('导出失败', 'Export failed'), ...
                    'Icon', 'error');
                return;
            end
            fclose(fid);
            obj.StatusLabel.Text = mps.tr('已导出参数集：%s', ...
                'Presets exported: %s', target);
        end
    end

    methods (Access = private)
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
end
