function out = preflight(varargin)
%PREFLIGHT Run local environment checks and optionally the full test suite.
%
%   out = mps.preflight()
%   out = mps.preflight('Full', false)
%   out = mps.preflight('LogDir', fullfile(pwd, 'logs'))
%
%   Every run writes a timestamped log under logs/ (gitignored).  This is a
%   local safety check only: no network access, no self-hosted runner, and no
%   remote code execution.

    root = fileparts(fileparts(mfilename('fullpath')));
    full = true;
    logDir = fullfile(root, 'logs');
    for k = 1:2:numel(varargin)
        if k + 1 > numel(varargin), break; end
        switch lower(char(varargin{k}))
            case 'full'
                full = logical(varargin{k+1});
            case 'logdir'
                logDir = char(varargin{k+1});
        end
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
    fprintf('Root: %s\n\n', root);

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
