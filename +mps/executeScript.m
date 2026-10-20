function out = executeScript(scriptPath, maxVariableMB, maxTotalMB, ...
    workspaceMatFile, lazyThresholdMB)
%EXECUTESCRIPT Run a script in an isolated function workspace.
%
%   The script is executed with run() inside this function.  Variables
%   created by the script stay in this function's workspace.  Small
%   workspaces are copied into a struct; large ones are saved directly to
%   workspaceMatFile and only a summary is returned, avoiding a second full
%   copy in memory.
%
%   Optional lazyThresholdMB controls when direct-to-MAT saving is used
%   (default 32 MB).

    if nargin < 2 || isempty(maxVariableMB)
        maxVariableMB = 100;
    end
    if nargin < 3 || isempty(maxTotalMB)
        maxTotalMB = 512;
    end
    if nargin < 4
        workspaceMatFile = '';
    end
    if nargin < 5 || isempty(lazyThresholdMB)
        lazyThresholdMB = 32;
    end

    % The script may call "clear", which would delete local variables such
    % as maxVariableMB.  Root appdata survives the script's workspace reset.
    lazyCfg = struct('matFile', workspaceMatFile, ...
        'thresholdMB', lazyThresholdMB);
    setappdata(0, 'mpsCaptureLimits', [maxVariableMB, maxTotalMB]);
    setappdata(0, 'mpsLazyWorkspace', lazyCfg);

    mpsErrorReport = '';
    try
        mpsScriptPath = scriptPath; %#ok<NASGU>
        run(mpsScriptPath);
    catch err
        mpsErrorReport = getReport(err, 'extended', 'hyperlinks', 'off');
    end

    limits = getappdata(0, 'mpsCaptureLimits');
    if isempty(limits)
        limits = [100, 512];
    end
    lazyCfg = getappdata(0, 'mpsLazyWorkspace');
    if isempty(lazyCfg)
        lazyCfg = struct('matFile', '', 'thresholdMB', 32);
    end
    cleanupCaptureLimits();

    mpsVars = whos;
    internal = {'mpsScriptPath', 'mpsErrorReport', 'ans', ...
        'maxVariableMB', 'maxTotalMB', 'limits', 'matFile', ...
        'lazyCfg', 'scriptPath', 'out', 'workspaceMatFile', ...
        'lazyThresholdMB', 'lazyThresholdBytes', 'useLazy', ...
        'internal', 'mpsVars', 'mpsKeep', 'err', ...
        'mpsNames', 'mpsTotal', 'mpsProjectOldPath', ...
        'mpsProjectCleanup', 'mpsProjectHere'};
    mpsKeep = ~ismember({mpsVars.name}, internal);
    mpsKeep = mpsKeep & ~cellfun(@(c) startsWith(c, 'matlab.ui.') || ...
        startsWith(c, 'matlab.graphics.'), {mpsVars.class});
    mpsNames = {mpsVars(mpsKeep).name};
    mpsTotal = sum([mpsVars(mpsKeep).bytes]);

    lazyThresholdBytes = lazyCfg.thresholdMB * 1024^2;
    useLazy = ~isempty(lazyCfg.matFile) && mpsTotal > lazyThresholdBytes;
    if useLazy
        if ~isempty(mpsNames)
            try
                if mpsTotal > 1.8e9
                    save(lazyCfg.matFile, mpsNames{:}, '-v7.3');
                else
                    save(lazyCfg.matFile, mpsNames{:});
                end
            catch err
                error('mps:executeScript:saveWorkspace', ...
                    '无法保存工作区：%s', err.message);
            end
        end
        summary = mps.summarizeWhos(mpsVars(mpsKeep));
        data = struct();
        matFile = lazyCfg.matFile;
    else
        data = mps.captureWorkspace(limits(1), limits(2));
        summary = mps.summarizeWorkspace(data);
        matFile = '';
    end

    if ~exist('mpsErrorReport', 'var')
        mpsErrorReport = '';
    end

    out = struct();
    out.ok = isempty(mpsErrorReport);
    out.error = mpsErrorReport;
    out.data = data;
    out.summary = summary;
    out.matFile = matFile;
    out.lazy = useLazy;
end

% -------------------------------------------------------------------------
function cleanupCaptureLimits()
    try
        if isappdata(0, 'mpsCaptureLimits')
            rmappdata(0, 'mpsCaptureLimits');
        end
        if isappdata(0, 'mpsLazyWorkspace')
            rmappdata(0, 'mpsLazyWorkspace');
        end
    catch
        % 清理失败不影响主流程
    end
end
