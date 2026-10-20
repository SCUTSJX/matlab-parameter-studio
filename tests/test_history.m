% test_history tests. Executed in the run_tests workspace.

    % --- 16. Run history + load parameters -------------------------------
    histRoot = fullfile(tempdir, 'mps_history_test');
    if isfolder(histRoot)
        rmdir(histRoot, 's');
    end
    mkdir(histRoot);
    wsData = struct('t', (0:0.1:1)', 'y', (0:0.1:1)');
    for hr = 1:2
        runDir = fullfile(histRoot, sprintf('20261019_12000%d', hr));
        mkdir(runDir);
        pH = mps.scan(demo);
        for hk = 1:numel(pH)
            if strcmp(pH(hk).name, 'k')
                pH(hk).newValue = num2str(4 * hr);
                pH(hk).use = true;
            end
        end
        rH = struct();
        rH.ok = true;
        rH.error = '';
        rH.figures = struct('path', {}, 'title', {}, 'figFile', {});
        rH.workspace = mps.summarizeWorkspace(wsData);
        rH.workspaceData = wsData;
        rH.log = '';
        rH.scriptPath = fullfile(runDir, 'run_script.m');
        rH.matFile = fullfile(runDir, 'workspace.mat');
        rH.elapsedSeconds = hr * 0.5;
        mps.writeReport(runDir, demo, pH, rH);
        save(fullfile(runDir, 'workspace.mat'), '-struct', 'wsData');
    end
    history = mps.listRuns(histRoot, 'SourceFile', demo);
    assert(numel(history) == 2, 'history should list two runs');
    assert(all([history.canLoad]), 'history runs should be loadable');
    assert(all([history.canCompare]), 'history runs should be comparable');
    assert(all([history.bytes] > 0), 'history should report run sizes');
    assert(~isempty(strfind(history(1).paramSummary, 'k=')), ...
        'history summary should mention changed k');

    [histValues, histMeta] = mps.loadRunParameters(history(1).path);
    assert(numel(histValues) == numel(pH), ...
        'history should load every parameter record');
    assert(strcmpi(histMeta.sourceFile, demo), ...
        'history metadata should keep the source file');
    presetH = struct('name', 'history', 'values', histValues);
    [pHist, statsH] = mps.applyPreset(mps.scan(demo), presetH);
    assert(statsH.matched == numel(histValues), ...
        'history values should apply to a fresh scan');
    assert(strcmp(pHist(find(strcmp({pHist.name}, 'k'), 1)).newValue, ...
        '4') || strcmp(pHist(find(strcmp({pHist.name}, 'k'), 1)).newValue, ...
        '8'), 'history preset should restore a swept value');

    histDlg = mps.RunHistoryDialog(histRoot, 'SourceFile', demo, ...
        'CurrentOutDir', history(1).path, 'Visible', 'off');
    assert(histDlg.runCount() == 2, 'history dialog should show both runs');
    delete(histDlg);
    fprintf('  run history: ok\n');

    % --- 17. Duplicate parameter names in compare ------------------------
    dupRoot = fullfile(tempdir, 'mps_dup_compare');
    if isfolder(dupRoot)
        rmdir(dupRoot, 's');
    end
    dupA = fullfile(dupRoot, 'a');
    dupB = fullfile(dupRoot, 'b');
    mkdir(dupA);
    mkdir(dupB);
    dupRecords = @(v1, v2) [ ...
        struct('name', 'switch_time', 'line', 10, 'value', '1', ...
        'newValue', v1, 'use', true, 'locked', false), ...
        struct('name', 'switch_time', 'line', 20, 'value', '3', ...
        'newValue', v2, 'use', true, 'locked', false)];
    fid = fopen(fullfile(dupA, 'parameters.json'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(dupRecords('2', '4')));
    fclose(fid);
    fid = fopen(fullfile(dupB, 'parameters.json'), 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(dupRecords('2', '9')));
    fclose(fid);
    mps.compareRuns(dupA, dupB, fullfile(dupB, 'compare.html'));
    cmp = jsondecode(fileread(fullfile(dupB, 'compare.json')));
    assert(numel(cmp.parameterDiffs) == 2, ...
        'duplicate names on different lines must stay separate');
    assert(any([cmp.parameterDiffs.lineA] == 10) && ...
        any([cmp.parameterDiffs.lineA] == 20), ...
        'compare should report the original line numbers');
    rmdir(dupRoot, 's');
    fprintf('  duplicate-name compare: ok\n');
