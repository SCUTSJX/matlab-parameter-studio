classdef ProjectSession
%PROJECTSESSION Pure project-loading model for App.
%
%   Keeps scanning, source-line loading and project stamps out of App so
%   App only applies the returned data to its widgets.

    methods (Static)
        function s = load(entryFile)
            entryFile = char(entryFile);
            s = struct('ok', false, 'error', '', 'entryFile', entryFile, ...
                'projectRoot', '', 'params', struct([]), ...
                'lines', {{}}, 'projectStamp', '', ...
                'sourceStamp', struct());
            if ~isfile(entryFile)
                s.error = sprintf('入口脚本不存在：\n%s', entryFile);
                return;
            end
            try
                p = mps.scanProject(fileparts(entryFile));
            catch err
                s.error = err.message;
                return;
            end
            if isempty(p)
                s.error = ['项目里没有识别到可调参数。请确认入口脚本所在目录下的 ' ...
                    '.m 文件。'];
                return;
            end
            try
                raw = fileread(entryFile);
            catch err
                s.error = err.message;
                return;
            end
            raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
            raw = strrep(raw, sprintf('\r'), sprintf('\n'));
            lines = regexp(raw, '\n', 'split');
            if ~isempty(lines) && isempty(lines{end})
                lines(end) = [];
            end
            s.ok = true;
            s.projectRoot = fileparts(entryFile);
            s.params = p;
            s.lines = lines;
            s.projectStamp = mps.projectStamp(s.projectRoot).signature;
            s.sourceStamp = mps.sourceStamp(entryFile);
        end

        function label = defaultFilter(labels)
            %DEFAULTFILTER Pick a catalog/config-style file when present.
            label = '';
            patterns = {'catalog', 'config', 'params', 'parameters', ...
                'setup', 'values'};
            for k = 1:numel(labels)
                for j = 1:numel(patterns)
                    if contains(lower(labels{k}), patterns{j})
                        label = labels{k};
                        return;
                    end
                end
            end
        end
    end
end
