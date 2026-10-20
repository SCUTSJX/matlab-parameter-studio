function out = preflight(varargin)
%PREFLIGHT Run local environment checks and optionally the full test suite.
%
%   out = mps.preflight()
%   out = mps.preflight('Full', false)
%   out = mps.preflight('LogDir', fullfile(pwd, 'logs'))
%   out = mps.preflight('KeepLogs', 10)
%
%   Every run writes a timestamped log under logs/ (gitignored) and removes
%   older preflight logs, keeping the newest KeepLogs entries (default 20).
%   Local paths in the log are replaced with <repo>, <temp> and <user> before
%   the log is closed, so a log can be shared more safely.
%
%   This is a local safety check only: no network access, no self-hosted
%   runner, and no remote code execution.

    root = fileparts(fileparts(mfilename('fullpath')));
    full = true;
    keepLogs = 20;
    logDir = fullfile(root, 'logs');
    for k = 1:2:numel(varargin)
        if k + 1 > numel(varargin), break; end
        switch lower(char(varargin{k}))
            case 'full'
                full = logical(varargin{k+1});
            case 'logdir'
                logDir = char(varargin{k+1});
            case 'keeplogs'
                keepLogs = double(varargin{k+1});
        end
    end
    if ~isscalar(keepLogs) || ~isfinite(keepLogs) || keepLogs < 1
        keepLogs = 20;
    end

    addpath(root);
    if ~isfolder(logDir)
        mkdir(logDir);
    end
    logFile = fullfile(logDir, sprintf('preflight_%s.log', ...
        datestr(now, 'yyyymmdd_HHMMSS')));
    out = struct('ok', false, 'logFile', logFile, ...
        'environment', struct(), 'testsRan', false, ...
        'testsPassed', false, 'error', '');

    diary off;
    diary(logFile);
    diaryCleaner = onCleanup(@() diary('off')); %#ok<NASGU>
    fprintf('MATLAB Parameter Studio preflight\n');
    fprintf('Time: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf('Root: <repo>\n\n');

    try
        out.environment = mps.checkEnvironment(root);
        fprintf('MATLAB %s (%s)\n', out.environment.matlabVersion, ...
            out.environment.release);
        fprintf('Parameter Studio %s\n', out.environment.mpsVersion);
        fprintf('PCT: %s\n', ternary(out.environment.hasPCT, 'yes', 'no'));
        for k = 1:numel(out.environment.messages)
            fprintf('NOTE: %s\n', out.environment.messages{k});
        end
        fprintf('\n');
        if ~out.environment.ok
            out.error = '环境检查未通过。';
        else
            if full
                fprintf('Running full test suite...\n\n');
                addpath(fullfile(root, 'tests'));
                try
                    run_tests;
                    out.testsRan = true;
                    out.testsPassed = true;
                catch err
                    out.testsRan = true;
                    out.testsPassed = false;
                    out.error = getReport(err, 'extended', ...
                        'hyperlinks', 'off');
                    fprintf('\nTEST FAILURE:\n%s\n', out.error);
                end
            else
                fprintf('Environment-only check (Full=false).\n');
            end
            out.ok = out.environment.ok && ...
                (~full || out.testsPassed);
        end
    catch err
        out.error = getReport(err, 'extended', 'hyperlinks', 'off');
        fprintf('\nPREFLIGHT FAILURE:\n%s\n', out.error);
    end

    fprintf('\nPreflight result: %s\n', ternary(out.ok, 'PASS', 'FAIL'));
    fprintf('Log: %s\n', logFile);
    diary off;
    clear diaryCleaner;

    redactLogFile(logFile, root, tempdir);
    cleanupPreflightLogs(logDir, keepLogs);

    if ~out.ok
        warning('mps:preflight:failed', ...
            'Preflight failed. See log: %s', logFile);
    end
end

% -------------------------------------------------------------------------
function value = ternary(condition, a, b)
    if condition
        value = a;
    else
        value = b;
    end
end

% -------------------------------------------------------------------------
function redactLogFile(logFile, root, tempDir)
    if ~isfile(logFile)
        return;
    end
    try
        fid = fopen(logFile, 'r');
        if fid < 0
            return;
        end
        bytes = fread(fid, Inf, '*uint8')';
        fclose(fid);

        replacements = {
            root, '<repo>'
            tempDir, '<temp>'
            getenv('USERPROFILE'), '<user>'
            getenv('HOME'), '<user>'
        };
        text = char(bytes);
        for k = 1:size(replacements, 1)
            pattern = replacements{k, 1};
            if isempty(pattern)
                continue;
            end
            variants = unique({pattern, strrep(pattern, '\', '/'), ...
                regexprep(pattern, '[\\/]$', '')});
            variants = variants(~cellfun(@isempty, variants));
            for v = 1:numel(variants)
                text = strrep(text, variants{v}, replacements{k, 2});
            end
        end

        fid = fopen(logFile, 'w');
        if fid < 0
            return;
        end
        fwrite(fid, uint8(text), 'uint8');
        fclose(fid);
    catch err
        mps.logWarning('脱敏 preflight 日志', err, 'Silent', true);
    end
end

% -------------------------------------------------------------------------
function cleanupPreflightLogs(logDir, keepLogs)
    keepLogs = max(1, round(double(keepLogs)));
    items = dir(fullfile(logDir, 'preflight_*.log'));
    items = items(~[items.isdir]);
    if numel(items) <= keepLogs
        return;
    end
    [~, order] = sort({items.name}, 'descend');
    items = items(order);
    for k = keepLogs + 1:numel(items)
        target = fullfile(logDir, items(k).name);
        try
            delete(target);
        catch err
            mps.logWarning(sprintf('清理旧 preflight 日志 %s', items(k).name), ...
                err, 'Silent', true);
        end
    end
end
