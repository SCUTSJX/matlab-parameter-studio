function run_tests()
%RUN_TESTS Self-contained checks for MATLAB Parameter Studio.
%
%   Run from MATLAB:
%       run_tests
%
%   The tests use the demo folder and temporary files only.

    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root);
    fprintf('== MATLAB Parameter Studio tests ==\n');

    % Keep the test run quiet: figures created by the demo scripts are
    % invisible, and any figures created during the tests are closed on
    % exit (the caller's existing figures are left alone).
    oldVis = get(groot, 'defaultFigureVisible');
    set(groot, 'defaultFigureVisible', 'off');
    beforeFigs = findall(groot, 'Type', 'figure');
    cleanupObj = onCleanup(@() cleanupTestFigures(oldVis, beforeFigs)); %#ok<NASGU>

    demo = fullfile(root, 'demo', 'demo_simulation.m');
    assert(isfile(demo), 'demo script missing');

    % --- 1. Detection -----------------------------------------------------
    p = mps.scan(demo);
    assert(numel(p) >= 7, 'expected at least 7 literals');
    names = {p.name};
    for expected = {'m', 'k', 'c', 'x0', 'v0', 'tEnd', 'dt'}
        assert(any(strcmp(names, expected{1})), ...
            sprintf('parameter %s not detected', expected{1}));
    end
    fprintf('  detection: %d literals, %d recommended\n', ...
        numel(p), sum([p.use]));

    % --- 2. Value validation ---------------------------------------------
    assert(mps.validateValue('2*pi'), '2*pi should be valid');
    assert(mps.validateValue('[1 2 3]'), 'array should be valid');
    assert(mps.validateValue('1:0.1:10'), 'range should be valid');
    [ok, ~] = mps.validateValue('delete(''x'')');
    assert(~ok, 'function calls must be rejected');

    % --- 3. Edit, run, report --------------------------------------------
    for k = 1:numel(p)
        switch p(k).name
            case 'm', p(k).newValue = '2'; p(k).use = true;
            case 'k', p(k).newValue = '8'; p(k).use = true;
            case 'c', p(k).newValue = '0.5'; p(k).use = true;
        end
    end
    outDir = fullfile(tempdir, 'mps_tests_run');
    if isfolder(outDir)
        rmdir(outDir, 's');
    end
    mkdir(outDir);
    scriptPath = fullfile(outDir, 'run_script.m');
    [~, applied] = mps.applyEdits(demo, p, scriptPath, ...
        'NeutralizeCloseAll', true);
    assert(numel(applied) == 3, 'expected 3 applied edits');

    r = mps.runScript(demo, scriptPath, outDir);
    assert(r.ok, r.error);
    assert(numel(r.figures) >= 1, 'expected at least one captured figure');
    assert(abs(r.workspaceData.k - 8) < 1e-12, 'k override did not run');
    assert(abs(r.workspaceData.c - 0.5) < 1e-12, 'c override did not run');
    reportPath = mps.writeReport(outDir, demo, p, r);
    assert(isfile(reportPath), 'report not written');
    fprintf('  run: %d figures, %d workspace variables\n', ...
        numel(r.figures), numel(r.workspace));

    % --- 4. Multi-line nested structs ------------------------------------
    structFile = fullfile(tempdir, 'mps_struct_test2.m');
    fid = fopen(structFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'r=struct(''a'',struct(''b'',1),...\n ''c'',struct(''d'',2));\n');
    fclose(fid);
    p2 = mps.scan(structFile);
    n2 = {p2.name};
    assert(any(strcmp(n2, 'r.a.b')), 'nested r.a.b not detected');
    assert(any(strcmp(n2, 'r.c.d')), 'nested r.c.d not detected');
    fprintf('  multi-line structs: ok\n');

    % --- 5. % @param annotations -----------------------------------------
    annoFile = fullfile(tempdir, 'mps_anno_test.m');
    fid = fopen(annoFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'figure(''Position'',[10 20 30 40]); %% @param layout\n');
    fclose(fid);
    p3 = mps.scan(annoFile);
    assert(~isempty(p3), 'annotated literals not detected');
    assert(all([p3.use]), '@param literals should be selected');
    assert(all(strcmp({p3.category}, 'annotated')), ...
        '@param category should be annotated');
    fprintf('  @param annotations: ok\n');

    % --- 6. AI annotation template + import ------------------------------
    annoPath = fullfile(tempdir, 'mps_annotation_template.json');
    mps.writeAnnotationTemplate(demo, p, annoPath);
    assert(isfile(annoPath), 'annotation template not written');
    j = jsondecode(fileread(annoPath));
    assert(isfield(j, 'parameters'), 'template must contain parameters');
    assert(numel(j.parameters) == numel(p), ...
        'template should contain one entry per parameter');
    assert(isfield(j, 'instructions'), 'template must contain instructions');

    % Compact name -> description map (easiest shape for an AI).
    mapPath = fullfile(tempdir, 'mps_annotation_map.json');
    fid = fopen(mapPath, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', ['{"m":"mass (kg)",' ...
        '"k":{"description":"spring stiffness","unit":"N/m"},' ...
        '"request.gains.eta":"learning rate"}']);
    fclose(fid);
    anns = mps.readAnnotations(mapPath);
    assert(numel(anns) == 3, 'map annotations should have 3 entries');
    [pAnn, statsAnn] = mps.applyAnnotations(p, anns);
    assert(statsAnn.matched == 2, 'm and k should match by name');
    mi = find(strcmp({pAnn.name}, 'm'), 1);
    assert(strcmp(pAnn(mi).description, 'mass (kg)'), 'm description missing');
    ki = find(strcmp({pAnn.name}, 'k'), 1);
    assert(strcmp(pAnn(ki).unit, 'N/m'), 'k unit missing');

    % Template round trip: fill the first entry and match it by id.
    j.parameters(1).description = '待确认的测试注释';
    j.parameters(1).unit = '';
    filledPath = fullfile(tempdir, 'mps_annotation_filled.json');
    fid = fopen(filledPath, 'w', 'n', 'UTF-8');
    fprintf(fid, '%s', jsonencode(j));
    fclose(fid);
    anns2 = mps.readAnnotations(filledPath);
    [~, stats2] = mps.applyAnnotations(p, anns2);
    assert(stats2.matched == 1, 'template entry should match by id');
    fprintf('  AI annotations: ok\n');

    % --- 7. Locked parameters --------------------------------------------
    pLock = mps.scan(demo);
    for k = 1:numel(pLock)
        switch pLock(k).name
            case 'm'
                pLock(k).locked = true;
                pLock(k).newValue = '2';
                pLock(k).use = true;
            case 'k'
                pLock(k).locked = false;
                pLock(k).newValue = '8';
                pLock(k).use = true;
        end
    end
    lockDir = fullfile(tempdir, 'mps_lock_test');
    if isfolder(lockDir)
        rmdir(lockDir, 's');
    end
    mkdir(lockDir);
    lockScript = fullfile(lockDir, 'run_script.m');
    [~, lockedApplied] = mps.applyEdits(demo, pLock, lockScript, ...
        'NeutralizeCloseAll', true);
    lockedNames = {lockedApplied.name};
    assert(~any(strcmp(lockedNames, 'm')), 'locked parameter m must not change');
    assert(any(strcmp(lockedNames, 'k')), 'unlocked parameter k should change');
    rLock = mps.runScript(demo, lockScript, lockDir);
    assert(abs(rLock.workspaceData.m - 1.0) < 1e-12, ...
        'locked m should keep its original value');
    assert(abs(rLock.workspaceData.k - 8) < 1e-12, ...
        'unlocked k should be overridden');
    fprintf('  locked parameters: ok\n');

    % --- 8. Compare two runs ---------------------------------------------
    pC = mps.scan(demo);
    for k = 1:numel(pC)
        switch pC(k).name
            case 'm', pC(k).newValue = '2'; pC(k).use = true;
            case 'k', pC(k).newValue = '6'; pC(k).use = true;
            case 'c', pC(k).newValue = '0.5'; pC(k).use = true;
        end
    end
    outDir2 = fullfile(tempdir, 'mps_tests_run2');
    if isfolder(outDir2)
        rmdir(outDir2, 's');
    end
    mkdir(outDir2);
    script2 = fullfile(outDir2, 'run_script.m');
    mps.applyEdits(demo, pC, script2, 'NeutralizeCloseAll', true);
    r2 = mps.runScript(demo, script2, outDir2);
    assert(r2.ok, r2.error);
    cmpPath = fullfile(outDir2, 'compare.html');
    mps.compareRuns(outDir, outDir2, cmpPath);
    assert(isfile(cmpPath), 'compare report not written');
    html = fileread(cmpPath);
    assert(contains(html, '参数对比'), 'compare report missing parameter table');
    assert(contains(html, '有差异'), 'compare report missing difference status');
    assert(isfile(fullfile(outDir2, 'compare.json')), ...
        'compare json not written');
    fprintf('  compare two runs: ok\n');

    % --- 9. Parameter presets --------------------------------------------
    presetDemo = fullfile(tempdir, 'mps_preset_demo.m');
    copyfile(demo, presetDemo);
    pP = mps.scan(presetDemo);
    for k = 1:numel(pP)
        switch pP(k).name
            case 'm', pP(k).newValue = '3'; pP(k).use = true;
            case 'k', pP(k).newValue = '9'; pP(k).use = true;
            case 'c'
                pP(k).locked = true;
                pP(k).newValue = pP(k).value;
                pP(k).use = true;
        end
    end
    mps.savePreset(presetDemo, '高刚度', pP);
    assert(isfile(mps.presetsPath(presetDemo)), 'preset file not written');
    rP = mps.readPresets(presetDemo);
    assert(numel(rP) == 1, 'expected one preset');
    assert(strcmp(rP(1).name, '高刚度'), 'preset name mismatch');
    pFresh = mps.scan(presetDemo);
    [pApplied, statsP] = mps.applyPreset(pFresh, rP(1));
    assert(statsP.matched >= 3, 'preset should match m, k and c');
    mi = find(strcmp({pApplied.name}, 'm'), 1);
    assert(strcmp(pApplied(mi).newValue, '3'), 'preset m value not applied');
    ci = find(strcmp({pApplied.name}, 'c'), 1);
    assert(pApplied(ci).locked, 'preset lock not applied');
    assert(strcmp(pApplied(ci).newValue, pApplied(ci).value), ...
        'locked preset entry must keep the original value');
    delete(mps.presetsPath(presetDemo));
    delete(presetDemo);
    fprintf('  parameter presets: ok\n');

    % --- 10. Batch sweep --------------------------------------------------
    vParse = mps.parseSweepValues('1,2,4');
    assert(isequal(vParse, [1 2 4]), 'comma list parse failed');
    vRange = mps.parseSweepValues('1:0.5:5');
    assert(numel(vRange) == 9, 'range parse failed');
    [~, pErr] = mps.parseSweepValues('abc');
    assert(~isempty(pErr), 'invalid sweep text should return an error');
    scen = mps.sweepScenarios({'k', 'c'}, {1:2:5, [0.1 0.2]}, 24);
    assert(numel(scen) == 6, 'cartesian product count mismatch');
    assert(contains(scen(1).label, 'k=1'), 'scenario label missing');

    pS = mps.scan(demo);
    sweepNames = {'k'};
    sweepValues = {[4 8]};
    sweepScen = mps.sweepScenarios(sweepNames, sweepValues, 24);
    assert(numel(sweepScen) == 2, 'sweep should have two scenarios');
    sweepRoot = fullfile(tempdir, 'mps_sweep_test');
    if isfolder(sweepRoot)
        rmdir(sweepRoot, 's');
    end
    mkdir(sweepRoot);
    sweepResults = struct('label', {}, 'runDir', {}, 'ok', {}, ...
        'error', {}, 'figures', {}, 'elapsed', {}, 'workspaceData', {});
    for k = 1:numel(sweepScen)
        runDir = fullfile(sweepRoot, sprintf('run_%02d', k));
        mkdir(runDir);
        pp = pS;
        ki = find(strcmp({pp.name}, 'k'), 1);
        pp(ki).newValue = num2str(sweepScen(k).values{1}, '%.10g');
        pp(ki).use = true;
        sp = fullfile(runDir, 'run_script.m');
        mps.applyEdits(demo, pp, sp, 'NeutralizeCloseAll', true);
        rr = mps.runScript(demo, sp, runDir);
        sweepResults(end+1) = struct('label', sweepScen(k).label, ...
            'runDir', runDir, 'ok', rr.ok, 'error', rr.error, ...
            'figures', {rr.figures}, 'elapsed', rr.elapsedSeconds, ...
            'workspaceData', {rr.workspaceData}); %#ok<AGROW>
    end
    assert(all([sweepResults.ok]), 'sweep run failed');
    sweepReport = mps.writeSweepReport(sweepRoot, demo, sweepNames, ...
        sweepValues, sweepScen, sweepResults, '');
    assert(isfile(sweepReport), 'sweep report not written');
    assert(contains(fileread(sweepReport), '批量扫描报告'), ...
        'sweep report title missing');
    fprintf('  batch sweep: ok\n');

    % --- 11. Sweep dialog (hidden) ----------------------------------------
    dlg = mps.SweepDialog(p, struct(), 'Visible', 'off');
    ki = find(strcmp({p.name}, 'k'), 1);
    dlg.setSweepText(ki, '4,8');
    dlg.start();
    dres = dlg.Result;
    delete(dlg);
    assert(isfield(dres, 'activeIdx') && numel(dres.scenarios) == 2, ...
        'sweep dialog did not build two scenarios');
    assert(dres.activeIdx == ki, 'sweep dialog active parameter mismatch');
    dlg2 = mps.SweepDialog(p, struct(), 'Visible', 'off');
    dlg2.cancel();
    assert(isempty(fieldnames(dlg2.Result)), 'cancel should return an empty result');
    delete(dlg2);
    fprintf('  sweep dialog: ok\n');

    % --- 12. Error messages point at the original file --------------------
    errFile = fullfile(tempdir, 'mps_error_test.m');
    fid = fopen(errFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 1;\nb = a + 1;\nerror(''this is a test error'');\n');
    fclose(fid);
    pE = mps.scan(errFile);
    errDir = fullfile(tempdir, 'mps_error_run');
    if isfolder(errDir)
        rmdir(errDir, 's');
    end
    mkdir(errDir);
    errScript = fullfile(errDir, 'run_script.m');
    mps.applyEdits(errFile, pE, errScript, 'NeutralizeCloseAll', true);
    rE = mps.runScript(errFile, errScript, errDir);
    assert(~rE.ok, 'the error script should fail');
    assert(contains(rE.error, 'mps_error_test'), ...
        'error should mention the original file name');
    assert(~contains(rE.error, 'run_script'), ...
        'error should not mention the generated temp script');
    fprintf('  error path mapping: ok\n');

    % --- 13. Function file detection -------------------------------------
    funcFile = fullfile(tempdir, 'mps_func_test.m');
    fid = fopen(funcFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'function y=f(x)\ny=x+1;\nend\n');
    fclose(fid);
    p4 = mps.scan(funcFile);
    assert(~isempty(p4), 'function bodies should still be scanned');
    fprintf('  function file scanning: ok\n');

    % --- 14. Bulk edit / paste -------------------------------------------
    pB = mps.scan(demo);
    ki = find(strcmp({pB.name}, 'k'), 1);
    [pB, sB] = mps.bulkEdit(pB, ki, 'scale', '2');
    assert(strcmp(pB(ki).newValue, '8'), 'scale should update k to 8');
    assert(sB.changed == 1, 'scale should report one change');
    pB(ki).locked = true;
    pB(ki).newValue = pB(ki).value;
    [pB, sB] = mps.bulkEdit(pB, ki, 'set', '10');
    assert(sB.skippedLocked == 1, 'locked parameter should be skipped');
    [pB, ~] = mps.bulkEdit(pB, ki, 'unlock', '');
    [pB, sB] = mps.applyPastedValues(pB, ki, {'3.5'});
    assert(strcmp(pB(ki).newValue, '3.5'), 'pasted value should be applied');
    assert(sB.changed == 1, 'paste should report one change');
    [pB, sB] = mps.bulkEdit(pB, ki, 'useoff', '');
    assert(~pB(ki).use && sB.changed == 1, 'useoff should clear use');

    dlgB = mps.BulkEditDialog(pB, ki, 1:numel(pB), 'Visible', 'off');
    dlgB.setScope('selected');
    dlgB.setOperation('scale');
    dlgB.setValue('2');
    dlgB.apply();
    resB = dlgB.Result;
    delete(dlgB);
    assert(isfield(resB, 'op') && strcmp(resB.op, 'scale'), ...
        'bulk dialog should return the selected operation');
    assert(isequal(resB.indices, ki), 'bulk dialog target row mismatch');
    fprintf('  bulk edit: ok\n');

    % --- 15. Sweep metrics + summary CSV ---------------------------------
    metrics = mps.sweepMetrics(sweepResults, 't', {'y'});
    assert(~isempty(metrics), 'sweep metrics should not be empty');
    assert(any(~isnan([metrics.finalValue])), ...
        'sweep metrics should include curve values');
    [sweepReport2, metricsCsv] = mps.writeSweepReport(sweepRoot, demo, ...
        sweepNames, sweepValues, sweepScen, sweepResults, '', metrics);
    assert(isfile(sweepReport2), 'sweep report should be rewritten');
    assert(isfile(metricsCsv), 'sweep summary CSV missing');
    assert(contains(fileread(sweepReport2), '结果指标'), ...
        'sweep report missing metrics section');
    assert(contains(fileread(metricsCsv), 'rms'), ...
        'sweep CSV missing rms column');
    fprintf('  sweep metrics: ok\n');

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

    % --- 18. App UI construction -----------------------------------------
    app = mps.App('Visible', 'off');
    app.loadFile(demo);
    assert(~isempty(app.Params), 'app should load the demo parameters');
    delete(app);
    fprintf('  app UI: ok\n');

    fprintf('ALL TESTS PASSED\n');
end

% -------------------------------------------------------------------------
function cleanupTestFigures(oldVis, beforeFigs)
    set(groot, 'defaultFigureVisible', oldVis);
    after = findall(groot, 'Type', 'figure');
    for k = 1:numel(after)
        if ~isvalid(after(k))
            continue;
        end
        if isempty(beforeFigs) || ~any(after(k) == beforeFigs)
            delete(after(k));
        end
    end
end
