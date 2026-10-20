function runs = listRuns(root, varargin)
%LISTRUNS Describe the run folders created by MATLAB Parameter Studio.
%
%   runs = mps.listRuns(root)
%   runs = mps.listRuns(root, 'SourceFile', sourceFile)
%
%   root is normally <script folder>/parameter_studio_runs.  The optional
%   SourceFile filter keeps runs whose run.json belongs to that script;
%   older runs without run.json are kept so existing folders still show up.
%
%   Returned fields:
%       name, path, created, sortKey, isSweep, ok, error, elapsed,
%       figureCount, changedCount, paramSummary, sourceFile,
%       reportPath, sweepReportPath, paramsPath, workspacePath,
%       canLoad, canCompare

    sourceFile = '';
    for k = 1:2:numel(varargin)
        if k + 1 > numel(varargin), break; end
        switch lower(char(varargin{k}))
            case 'sourcefile'
                sourceFile = char(varargin{k+1});
        end
    end

    runs = emptyRuns();
    if isempty(root) || ~isfolder(root)
        return;
    end

    info = dir(root);
    for k = 1:numel(info)
        d = info(k);
        if ~d.isdir || isempty(d.name) || d.name(1) == '.'
            continue;
        end
        runPath = fullfile(root, d.name);
        reportPath = fullfile(runPath, 'report.html');
        sweepReportPath = fullfile(runPath, 'sweep_report.html');
        paramsPath = fullfile(runPath, 'parameters.json');
        workspacePath = fullfile(runPath, 'workspace.mat');
        sweepJsonPath = fullfile(runPath, 'sweep.json');
        runJsonPath = fullfile(runPath, 'run.json');

        if ~any(isfile({reportPath, sweepReportPath, paramsPath, ...
                workspacePath, sweepJsonPath, runJsonPath}))
            continue;   % empty or half-created folder
        end

        meta = readJson(runJsonPath);
        isSweep = isfile(sweepReportPath) || isfile(sweepJsonPath) || ...
            logicalField(meta, 'isSweep', false);

        runSource = charField(meta, 'sourceFile');
        if ~isempty(sourceFile) && ~isempty(runSource) && ...
                ~strcmpi(runSource, sourceFile)
            continue;
        end

        r = struct();
        r.name = d.name;
        r.path = runPath;
        r.sortKey = d.datenum;
        r.isSweep = logical(isSweep);
        r.sourceFile = runSource;
        r.reportPath = '';
        r.sweepReportPath = '';
        if isfile(sweepReportPath)
            r.sweepReportPath = sweepReportPath;
        end
        if isfile(reportPath)
            r.reportPath = reportPath;
        elseif isfile(sweepReportPath)
            r.reportPath = sweepReportPath;
        end
        r.bytes = folderBytes(runPath);
        r.paramsPath = '';
        if isfile(paramsPath)
            r.paramsPath = paramsPath;
        end
        r.workspacePath = '';
        if isfile(workspacePath)
            r.workspacePath = workspacePath;
        end

        r.created = charField(meta, 'created');
        if isempty(r.created)
            r.created = datestr(d.datenum, 'yyyy-mm-dd HH:MM:SS');
        end
        r.error = charField(meta, 'error');
        r.elapsed = numberField(meta, 'elapsedSeconds', NaN);
        r.changedCount = 0;
        r.paramSummary = '';
        r.figureCount = 0;

        if r.isSweep
            [summary, count, failures, elapsed, figures] = ...
                summarizeSweep(sweepJsonPath, runPath);
            r.paramSummary = summary;
            r.figureCount = figures;
            r.elapsed = elapsed;
            r.error = charField(meta, 'error');
            if ~isempty(failures)
                r.ok = double(failures == 0);
                if failures > 0
                    r.error = sprintf('%d 组运行失败', failures);
                end
            elseif isfield(meta, 'ok')
                r.ok = double(logical(meta.ok));
            else
                r.ok = NaN;
            end
            r.changedCount = 0;   % a sweep has no single parameter set
        else
            [summary, changed] = summarizeParams(paramsPath);
            r.paramSummary = summary;
            r.changedCount = changed;
            r.figureCount = countFigures(fullfile(runPath, 'figures'));
            r.ok = statusFromMetaOrReport(meta, reportPath);
            if isfield(meta, 'figureCount')
                r.figureCount = numberField(meta, 'figureCount', r.figureCount);
            end
        end

        % Old reports can still tell us whether the run failed.
        if isnan(r.ok) && isfile(r.reportPath)
            r.ok = statusFromReport(r.reportPath);
        end

        r.canLoad = ~r.isSweep && isfile(r.paramsPath);
        r.canCompare = isfile(r.paramsPath) && isfile(r.workspacePath);
        runs(end+1) = r; %#ok<AGROW>
    end

    if ~isempty(runs)
        [~, order] = sort([runs.sortKey], 'descend');
        runs = runs(order);
    end
end

% -------------------------------------------------------------------------
function runs = emptyRuns()
    runs = struct('name', {}, 'path', {}, 'created', {}, 'sortKey', {}, ...
        'isSweep', {}, 'ok', {}, 'error', {}, 'elapsed', {}, ...
        'figureCount', {}, 'changedCount', {}, 'paramSummary', {}, ...
        'bytes', {}, 'sourceFile', {}, 'reportPath', {}, 'sweepReportPath', {}, ...
        'paramsPath', {}, 'workspacePath', {}, 'canLoad', {}, ...
        'canCompare', {});
end

% -------------------------------------------------------------------------
function data = readJson(path)
    data = struct();
    if isempty(path) || ~isfile(path)
        return;
    end
    try
        value = jsondecode(fileread(path));
        if isstruct(value)
            data = value;
        end
    catch
    end
end

% -------------------------------------------------------------------------
function records = parameterRecords(path)
    records = struct([]);
    if isempty(path) || ~isfile(path)
        return;
    end
    data = readJson(path);
    if isempty(data)
        return;
    end
    if iscell(data)
        data = [data{:}];
    end
    if isstruct(data)
        records = data;
    end
end

% -------------------------------------------------------------------------
function [summary, changed] = summarizeParams(path)
    summary = '';
    changed = 0;
    records = parameterRecords(path);
    if isempty(records)
        return;
    end
    parts = {};
    for k = 1:numel(records)
        r = records(k);
        use = logicalField(r, 'use', true);
        name = charField(r, 'name');
        value = valueField(r, 'value');
        newValue = valueField(r, 'newValue');
        if use && ~isempty(name) && ~strcmp(strtrim(value), strtrim(newValue))
            changed = changed + 1;
            if numel(parts) < 3
                parts{end+1} = sprintf('%s=%s', name, newValue); %#ok<AGROW>
            end
        end
    end
    if changed == 0
        summary = '未改参数';
    else
        if changed > numel(parts)
            parts{end+1} = sprintf('+%d', changed - numel(parts));
        end
        summary = strjoin(parts, ', ');
    end
end

% -------------------------------------------------------------------------
function [summary, count, failures, elapsed, figures] = ...
        summarizeSweep(sweepPath, runPath)
    summary = '批量扫描';
    count = NaN;
    failures = [];
    elapsed = NaN;
    figures = 0;

    if isempty(sweepPath) || ~isfile(sweepPath)
        return;
    end
    data = readJson(sweepPath);
    if isempty(data)
        return;
    end

    names = {};
    if isfield(data, 'names')
        rawNames = data.names;
        if ischar(rawNames)
            names = {rawNames};
        elseif iscell(rawNames)
            names = cellfun(@char, rawNames, 'UniformOutput', false);
        end
    end

    if isfield(data, 'results')
        results = data.results;
        if iscell(results)
            results = [results{:}];
        end
        if isstruct(results)
            count = numel(results);
            failures = 0;
            elapsed = 0;
            for k = 1:numel(results)
                if ~logicalField(results(k), 'ok', true)
                    failures = failures + 1;
                end
                elapsed = elapsed + numberField(results(k), 'elapsed', 0);
                figures = figures + numberField(results(k), 'figureCount', 0);
            end
        end
    end

    if isnan(count)
        runDirs = dir(fullfile(runPath, 'run_*'));
        count = sum([runDirs.isdir]);
    end
    if isfile(fullfile(runPath, 'overlay.png'))
        figures = figures + 1;
    end

    if isempty(names)
        summary = sprintf('批量扫描 · %d 组', count);
    else
        summary = sprintf('%s · %d 组', strjoin(names, ', '), count);
    end
    if ~isempty(failures) && failures > 0
        summary = sprintf('%s（%d 组失败）', summary, failures);
    end
end

% -------------------------------------------------------------------------
function bytes = folderBytes(folder)
    bytes = 0;
    try
        items = dir(fullfile(folder, '**', '*'));
        for k = 1:numel(items)
            if ~items(k).isdir
                bytes = bytes + items(k).bytes;
            end
        end
    catch
    end
end

% -------------------------------------------------------------------------
function n = countFigures(figDir)
    n = 0;
    if isfolder(figDir)
        files = dir(fullfile(figDir, '*.png'));
        n = numel(files);
    end
end

% -------------------------------------------------------------------------
function ok = statusFromMetaOrReport(meta, reportPath)
    if isfield(meta, 'ok')
        ok = double(logical(meta.ok));
        return;
    end
    ok = statusFromReport(reportPath);
end

% -------------------------------------------------------------------------
function ok = statusFromReport(reportPath)
    ok = NaN;
    if isempty(reportPath) || ~isfile(reportPath)
        return;
    end
    try
        html = fileread(reportPath);
        tok = regexp(html, '<b class="(ok|bad)">([^<]+)</b>', ...
            'tokens', 'once');
        if ~isempty(tok)
            ok = double(strcmp(tok{1}, 'ok'));
        elseif contains(html, '运行失败')
            ok = 0;
        elseif contains(html, '运行报告')
            ok = 1;
        end
    catch
    end
end

% -------------------------------------------------------------------------
function s = charField(item, name)
    s = '';
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if ischar(value)
        s = value;
    elseif isstring(value) && isscalar(value)
        s = char(value);
    end
end

% -------------------------------------------------------------------------
function s = valueField(item, name)
    s = '';
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if ischar(value)
        s = value;
    elseif isstring(value) && isscalar(value)
        s = char(value);
    elseif isnumeric(value) || islogical(value)
        s = num2str(value);
    end
end

% -------------------------------------------------------------------------
function v = numberField(item, name, defaultValue)
    v = defaultValue;
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if isnumeric(value) && isscalar(value) && ~isnan(value)
        v = double(value);
    end
end

% -------------------------------------------------------------------------
function v = logicalField(item, name, defaultValue)
    v = defaultValue;
    if ~isstruct(item) || ~isfield(item, name)
        return;
    end
    value = item.(name);
    if islogical(value) || isnumeric(value)
        if ~isempty(value)
            v = logical(value(1));
        end
    end
end
