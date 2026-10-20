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
            [file, path] = uiputfile({'*.m', 'MATLAB 脚本 (*.m)'}, ...
                '保存调参后的脚本', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            if strcmpi(target, sourceFile)
                obj.alert('不能覆盖原文件。请使用 _tuned 后缀或其他文件名。', ...
                    '保存失败', 'Icon', 'warning');
                return;
            end

            stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            footer = sprintf('%% ---- MATLAB Parameter Studio overrides (%s) ----\n', stamp);
            footer = [footer, sprintf('%% 源文件: %s\n', sourceFile)];
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
                    footer = [footer, sprintf('%%   %s = %s  (原值 %s, 第 %d 行)%s\n', ...
                        p.name, p.newValue, p.value, p.line, annSuffix)]; %#ok<AGROW>
                    anyChange = true;
                end
            end
            if ~anyChange
                footer = [footer, sprintf('%%   本次没有修改参数。\n')];
            end

            try
                original = fileread(sourceFile);
                [outText, applied] = mps.applyEdits(sourceFile, ...
                    params, '', 'Footer', footer);
            catch err
                obj.alert(err.message, '保存失败', 'Icon', 'error');
                return;
            end

            diffLines = mps.textDiff(original, outText);
            dlg = mps.DiffDialog(sprintf('保存到：%s', target), diffLines);
            uiwait(dlg.UIFigure);
            confirmed = dlg.Result;
            delete(dlg);
            if ~confirmed
                obj.StatusLabel.Text = '已取消保存。';
                return;
            end

            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                obj.alert('无法写入目标文件。', '保存失败', 'Icon', 'error');
                return;
            end
            try
                fprintf(fid, '%s', outText);
            catch err
                fclose(fid);
                obj.alert(err.message, '保存失败', 'Icon', 'error');
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
                    obj.alert(err.message, '保存失败', 'Icon', 'error');
                    return;
                end
                fclose(fid);
            end

            obj.StatusLabel.Text = sprintf('已保存调参脚本：%s', target);
            obj.alert(sprintf( ...
                '已保存脚本：\n%s\n\n参数记录：\n%s\n\n脚本可以直接在 MATLAB 中运行。', ...
                target, jsonPath), '保存成功', 'Icon', 'info');
        end

        function exportParams(obj, sourceFile, params)
            if isempty(sourceFile)
                return;
            end
            [~, base] = fileparts(sourceFile);
            defaultName = fullfile(fileparts(sourceFile), [base '_params.json']);
            [file, path] = uiputfile({'*.json', 'JSON 文件 (*.json)'}, ...
                '导出参数集', defaultName);
            if isequal(file, 0)
                return;
            end
            target = fullfile(path, file);
            fid = fopen(target, 'w', 'n', 'UTF-8');
            if fid < 0
                obj.alert('无法写入文件。', '导出失败', 'Icon', 'error');
                return;
            end
            try
                fprintf(fid, '%s', jsonencode(params));
            catch err
                fclose(fid);
                obj.alert(err.message, '导出失败', 'Icon', 'error');
                return;
            end
            fclose(fid);
            obj.StatusLabel.Text = sprintf('已导出参数集：%s', target);
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
