classdef RunExecutor < handle
%RUNEXECUTOR Execute one tuned script and produce its report.
%
%   ex = mps.RunExecutor(sourceFile, params, keepFigures);
%   ex.Progress = @(message) ...;
%   out = ex.run();
%
%   out fields: run (mps.runScript result), outDir, reportPath, params.
%
%   The executor owns the generated-script lifecycle, the invisible-figure
%   window and report writing.  The app keeps all UI updates and user
%   prompts.

    properties
        SourceFile = ''
        Params = struct([])
        KeepFigures = false
        MaxVariableMB = 100
        MaxTotalMB = 512
        Progress = @(message) []
    end

    methods
        function obj = RunExecutor(sourceFile, params, keepFigures)
            obj.SourceFile = char(sourceFile);
            obj.Params = params;
            if nargin >= 3
                obj.KeepFigures = logical(keepFigures);
            end
        end

        function out = run(obj)
            if isempty(obj.SourceFile)
                error('mps:RunExecutor:noSource', '没有源文件。');
            end
            params = obj.Params;
            for k = 1:numel(params)
                if params(k).use
                    [ok, ~] = mps.validateValue(params(k).newValue);
                    if ~ok
                        error('mps:RunExecutor:invalidValue', ...
                            '参数 %s 的新值无效：%s', ...
                            params(k).name, params(k).newValue);
                    end
                end
            end

            outDir = obj.makeOutputDir();
            keepScript = fullfile(outDir, 'run_script.m');
            sourceDir = fileparts(obj.SourceFile);
            tempScript = fullfile(sourceDir, ...
                sprintf('mps_run_%s.m', datestr(now, 'yyyymmdd_HHMMSSFFF')));
            try
                mps.applyEdits(obj.SourceFile, params, tempScript, ...
                    'NeutralizeCloseAll', true);
            catch
                tempScript = keepScript;
                mps.applyEdits(obj.SourceFile, params, tempScript, ...
                    'NeutralizeCloseAll', true);
            end
            scriptCleaner = onCleanup(@() ...
                obj.cleanupTempScript(tempScript, keepScript)); %#ok<NASGU>

            obj.Progress('运行 MATLAB 脚本...');
            oldFigVis = get(groot, 'defaultFigureVisible');
            set(groot, 'defaultFigureVisible', 'off');
            figVisCleaner = onCleanup(@() set(groot, ...
                'defaultFigureVisible', oldFigVis)); %#ok<NASGU>

            r = mps.runScript(obj.SourceFile, tempScript, outDir, ...
                'MaxVariableMB', obj.MaxVariableMB, ...
                'MaxTotalMB', obj.MaxTotalMB);
            clear figVisCleaner;
            obj.handleFigures(r);

            try
                if ~isfile(keepScript) && ~strcmpi(tempScript, keepScript)
                    copyfile(tempScript, keepScript);
                end
                if isfile(keepScript)
                    r.scriptPath = keepScript;
                end
            catch
            end
            clear scriptCleaner;

            obj.Progress('生成 HTML 报告...');
            reportPath = mps.writeReport(outDir, obj.SourceFile, params, r);

            out = struct('run', r, 'outDir', outDir, ...
                'reportPath', reportPath, 'params', params);
        end
    end

    methods (Access = private)
        function outDir = makeOutputDir(obj)
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            base = fileparts(obj.SourceFile);
            root = fullfile(base, 'parameter_studio_runs');
            try
                if ~isfolder(root)
                    mkdir(root);
                end
                outDir = fullfile(root, stamp);
                n = 2;
                while isfolder(outDir)
                    outDir = fullfile(root, sprintf('%s_%d', stamp, n));
                    n = n + 1;
                end
                mkdir(outDir);
            catch
                root = fullfile(tempdir, 'matlab_parameter_studio_runs');
                if ~isfolder(root)
                    mkdir(root);
                end
                outDir = fullfile(root, stamp);
                if isfolder(outDir)
                    outDir = fullfile(root, [stamp '_' num2str(randi(9999))]);
                end
                mkdir(outDir);
            end
        end

        function handleFigures(obj, r)
            if obj.KeepFigures
                for k = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(k))
                        set(r.figureHandles(k), 'Visible', 'on');
                    end
                end
            else
                for k = 1:numel(r.figureHandles)
                    if isvalid(r.figureHandles(k))
                        delete(r.figureHandles(k));
                    end
                end
                r.figureHandles = gobjects(0);
            end
        end

        function cleanupTempScript(~, tempScript, keepScript)
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript) && ...
                    ~isfile(keepScript)
                try
                    copyfile(tempScript, keepScript);
                catch
                end
            end
            if ~strcmpi(tempScript, keepScript) && isfile(tempScript)
                try
                    delete(tempScript);
                catch
                end
            end
        end
    end
end
