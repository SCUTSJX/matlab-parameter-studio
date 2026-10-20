classdef ProjectRunExecutor < handle
%PROJECTRUNEXECUTOR Run an entry script with edits in a shadow project.
%
%   Ex = mps.ProjectRunExecutor(sourceFile, entryFile, params, keepFigures)
%   out = Ex.run()
%
%   sourceFile is the file whose parameters are being edited (often a
%   configuration function), entryFile is the project script that should be
%   executed (for example run_P156.m).  The project is copied to a temporary
%   shadow folder, edits are applied there, and the entry script runs in that
%   shadow so the original project is never modified.

    properties
        SourceFile = ''
        EntryFile = ''
        Params = struct([])
        KeepFigures = false
        MaxVariableMB = 100
        MaxTotalMB = 512
        LazyWorkspaceMB = 32
        SaveFigFiles = false
        FigureResolution = 150
        OutDir = ''
        CopyProjectResults = true
        UseShadowCache = true
        ResetShadowResults = true
        SlimWorkspace = false
        SlimNames = {}
        Progress = @(message) []
    end

    methods
        function obj = ProjectRunExecutor(sourceFile, entryFile, params, keepFigures)
            obj.SourceFile = char(sourceFile);
            obj.EntryFile = char(entryFile);
            obj.Params = params;
            obj.KeepFigures = logical(keepFigures);
        end

        function out = run(obj)
            if isempty(obj.SourceFile) || isempty(obj.EntryFile)
                error('mps:ProjectRunExecutor:noFiles', ...
                    '参数源和入口脚本都必须指定。');
            end
            if isempty(obj.EntryFile) || ~isfile(obj.EntryFile)
                error('mps:ProjectRunExecutor:missingEntry', ...
                    '入口脚本不存在：%s', obj.EntryFile);
            end

            projectRoot = fileparts(obj.EntryFile);
            relativeEntry = relativeTo(projectRoot, obj.EntryFile);
            if isempty(relativeEntry)
                relativeEntry = obj.EntryFile;
            end

            if obj.UseShadowCache
                obj.Progress('同步项目影子目录...');
                shadowRoot = mps.prepareShadowProject(projectRoot);
                cleaner = onCleanup(@() []); %#ok<NASGU>
            else
                shadowRoot = fullfile(tempdir, sprintf( ...
                    'mps_project_%s_%d', datestr(now, 'yyyymmdd_HHMMSSFFF'), ...
                    randi(1e9)));
                cleaner = onCleanup(@() cleanupTree(shadowRoot)); %#ok<NASGU>
                obj.Progress('复制项目到临时目录...');
                mps.copyProjectTree(projectRoot, shadowRoot);
            end
            if obj.ResetShadowResults
                shadowResults = fullfile(shadowRoot, '运行结果');
                if isfolder(shadowResults)
                    try
                        rmdir(shadowResults, 's');
                    catch err
                        mps.logWarning('清理影子运行结果', err);
                    end
                end
            end

            if any(arrayfun(@(p) isfield(p, 'manual') && logical(p.manual), ...
                    obj.Params))
                error('mps:ProjectRunExecutor:manual', ...
                    '项目模式暂不支持手动参数。');
            end
            obj.Progress('写入调参后的配置...');
            files = unique({obj.Params.sourceFile});
            for k = 1:numel(files)
                file = files{k};
                if isempty(file)
                    continue;
                end
                rel = relativeTo(projectRoot, file);
                if isempty(rel)
                    error('mps:ProjectRunExecutor:outsideProject', ...
                        '参数文件不在入口脚本所在项目内：%s', file);
                end
                shadowFile = fullfile(shadowRoot, rel);
                if ~isfile(shadowFile)
                    error('mps:ProjectRunExecutor:missingSource', ...
                        '临时项目里找不到参数文件：%s', rel);
                end
                subset = obj.Params(strcmp({obj.Params.sourceFile}, file));
                mps.applyEdits(file, subset, shadowFile, ...
                    'NeutralizeCloseAll', true);
            end

            wrapper = fullfile(shadowRoot, 'mps_project_wrapper.m');
            writeWrapper(wrapper, relativeEntry);
            outDir = obj.makeOutputDir();
            keepScript = fullfile(outDir, 'run_script.m');

            obj.Progress('运行项目入口...');
            oldVis = get(groot, 'defaultFigureVisible');
            set(groot, 'defaultFigureVisible', 'off');
            figCleaner = onCleanup(@() set(groot, ...
                'defaultFigureVisible', oldVis)); %#ok<NASGU>

            r = mps.runScript(obj.EntryFile, wrapper, outDir, ...
                'MaxVariableMB', obj.MaxVariableMB, ...
                'MaxTotalMB', obj.MaxTotalMB, ...
                'LazyWorkspaceMB', obj.LazyWorkspaceMB, ...
                'SaveFigFiles', obj.SaveFigFiles, ...
                'FigureResolution', obj.FigureResolution);
            if obj.SlimWorkspace
                if isempty(r.workspaceData) && ~isempty(r.matFile) && ...
                        isfile(r.matFile)
                    r.workspaceData = loadSelected(r.matFile, obj.SlimNames);
                else
                    r.workspaceData = slimWorkspaceData( ...
                        r.workspaceData, obj.SlimNames);
                end
            end
            clear figCleaner;
            obj.handleFigures(r);

            try
                if isfile(wrapper) && ~strcmpi(wrapper, keepScript)
                    copyfile(wrapper, keepScript);
                end
                if isfile(keepScript)
                    r.scriptPath = keepScript;
                end
            catch err
                mps.logWarning('保存项目运行脚本副本', err);
            end

            % Preserve the project's own result folder (metrics.csv,
            % summary.mat, optional experiment plots) in the run directory.
            shadowResults = fullfile(shadowRoot, '运行结果');
            if obj.CopyProjectResults && isfolder(shadowResults)
                try
                    copyProjectTree(shadowResults, ...
                        fullfile(outDir, 'project_results'));
                catch err
                    mps.logWarning('复制项目运行结果', err);
                end
            end

            r.error = replaceShadowRoot(r.error, shadowRoot, projectRoot);
            r.log = replaceShadowRoot(r.log, shadowRoot, projectRoot);

            obj.Progress('生成 HTML 报告...');
            reportPath = mps.writeReport(outDir, ...
                obj.EntryFile, obj.Params, r);
            out = struct('run', r, 'outDir', outDir, ...
                'reportPath', reportPath, 'params', obj.Params, ...
                'shadowRoot', shadowRoot);
        end
    end

    methods (Access = private)
        function outDir = makeOutputDir(obj)
            if ~isempty(obj.OutDir)
                outDir = char(obj.OutDir);
                if ~isfolder(outDir)
                    mkdir(outDir);
                end
                return;
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            root = fullfile(fileparts(obj.EntryFile), 'parameter_studio_runs');
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
    end
end

% -------------------------------------------------------------------------
function slim = loadSelected(matFile, names)
    slim = struct();
    names = names(~cellfun(@isempty, names));
    names = names(~strcmp(names, '(无)'));
    if isempty(names), return; end
    try
        S = load(matFile, names{:});
        for k = 1:numel(names)
            if isfield(S, names{k}) && ...
                    (isnumeric(S.(names{k})) || islogical(S.(names{k}))) && ...
                    isvector(S.(names{k}))
                slim.(names{k}) = S.(names{k});
            end
        end
    catch err
        mps.logWarning('加载项目曲线变量', err);
    end
end

% -------------------------------------------------------------------------
function slim = slimWorkspaceData(ws, names)
    slim = struct();
    if ~isstruct(ws)
        return;
    end
    for k = 1:numel(names)
        name = char(names{k});
        if isempty(name) || strcmp(name, '(无)')
            continue;
        end
        if isfield(ws, name)
            v = ws.(name);
            if (isnumeric(v) || islogical(v)) && isvector(v)
                slim.(name) = v;
            end
        end
    end
end

% -------------------------------------------------------------------------
function rel = relativeTo(root, file)
    root = char(root);
    file = char(file);
    prefix = [root filesep];
    if strncmpi(file, prefix, numel(prefix))
        rel = file(numel(prefix)+1:end);
    else
        rel = '';
    end
end

% -------------------------------------------------------------------------
function writeWrapper(path, relativeEntry)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:ProjectRunExecutor:wrapper', ...
            '无法写入临时入口脚本：%s', path);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, 'mpsProjectOldPath = path;\n');
    fprintf(fid, 'mpsProjectCleanup = onCleanup(@() path(mpsProjectOldPath));\n');
    fprintf(fid, 'mpsProjectHere = fileparts(mfilename(''fullpath''));\n');
    fprintf(fid, 'run(fullfile(mpsProjectHere, ''%s''));\n', ...
        strrep(relativeEntry, '''', ''''''));
    clear cleaner;
end

% -------------------------------------------------------------------------
function txt = replaceShadowRoot(txt, shadowRoot, projectRoot)
    if isempty(txt)
        return;
    end
    try
        txt = strrep(txt, shadowRoot, projectRoot);
    catch
        % 替换失败时保留原文本
    end
end

% -------------------------------------------------------------------------
function cleanupTree(path)
    if isfolder(path)
        try
            rmdir(path, 's');
        catch err
            mps.logWarning('清理临时项目目录', err, 'Silent', true);
        end
    end
end
