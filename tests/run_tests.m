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

    limitedDir = fullfile(tempdir, 'mps_limited_run');
    if isfolder(limitedDir)
        rmdir(limitedDir, 's');
    end
    rLimited = mps.runScript(demo, scriptPath, limitedDir, ...
        'MaxVariableMB', 0, 'MaxTotalMB', 0.001);
    assert(rLimited.ok, rLimited.error);
    assert(isempty(fieldnames(rLimited.workspaceData)), ...
        'workspace capture limit should skip oversized variables');
    fprintf('  workspace capture limit: ok\n');

    % --- 3b. Reused figure capture ---------------------------------------
    reuseFig = figure(1);
    clf(reuseFig);
    reuseAx = axes(reuseFig); %#ok<LAXES>
    plot(reuseAx, 1:3);
    drawnow;
    reuseScript = fullfile(tempdir, 'mps_reuse_figure.m');
    fid = fopen(reuseScript, 'w', 'n', 'UTF-8');
    fprintf(fid, 'figure(1); clf; plot(1:5); title(''reused'');\n');
    fclose(fid);
    reuseDir = fullfile(tempdir, 'mps_reuse_figure_run');
    if isfolder(reuseDir)
        rmdir(reuseDir, 's');
    end
    rReuse = mps.runScript(reuseScript, reuseScript, reuseDir);
    assert(rReuse.ok, rReuse.error);
    assert(numel(rReuse.figures) == 1, ...
        'a reused, changed figure should be captured');
    close(reuseFig);
    delete(reuseScript);
    fprintf('  reused figure capture: ok\n');

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

    % --- 5b. % @ignore ---------------------------------------------------
    ignoreFile = fullfile(tempdir, 'mps_ignore_test.m');
    fid = fopen(ignoreFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'x = 1; %% @ignore\ny = 2;\n');
    fclose(fid);
    pIgn = mps.scan(ignoreFile);
    xi = find(strcmp({pIgn.name}, 'x'), 1);
    assert(~isempty(xi), '@ignore parameter should still be detected');
    assert(pIgn(xi).ignored, '@ignore should mark the parameter');
    assert(~pIgn(xi).use, '@ignore parameter must not be selected');
    assert(strcmp(pIgn(xi).category, 'ignored'), ...
        '@ignore should set the ignored category');
    delete(ignoreFile);
    fprintf('  @ignore: ok\n');

    % --- 5c. Manual parameters -------------------------------------------
    manualDemo = fullfile(tempdir, 'mps_manual_demo.m');
    fid = fopen(manualDemo, 'w', 'n', 'UTF-8');
    fprintf(fid, 'y = x + 1;\n');
    fclose(fid);
    pManual = mps.scan(manualDemo);
    manualParam = mps.makeManualParam(manualDemo, 'x', '5', '手动输入', '');
    pManual = [pManual, manualParam];
    mps.writeManualParams(manualDemo, pManual);
    loadedManual = mps.readManualParams(manualDemo);
    assert(numel(loadedManual) == 1, 'manual parameter should round trip');
    manualText = mps.applyEdits(manualDemo, pManual, '');
    assert(contains(manualText, 'x = 5;'), ...
        'manual parameter should be prepended');
    manualExec = mps.RunExecutor(manualDemo, pManual, false);
    manualExec.Progress = @(msg) [];
    manualRun = manualExec.run();
    assert(manualRun.run.ok, 'manual parameter run failed');
    assert(abs(manualRun.run.workspaceData.x - 5) < 1e-12 && ...
        abs(manualRun.run.workspaceData.y - 6) < 1e-12, ...
        'manual parameter should be visible to the script');
    manualRoot = fullfile(fileparts(manualDemo), 'parameter_studio_runs');
    if isfolder(manualRoot)
        rmdir(manualRoot, 's');
    end
    delete(manualDemo);
    delete(mps.manualParamsPath(manualDemo));
    fprintf('  manual parameters: ok\n');

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

    % --- 18. Undo / redo + session restore -------------------------------
    sessionDemo = fullfile(tempdir, 'mps_session_demo.m');
    copyfile(demo, sessionDemo);
    sessionFile = mps.sessionPath(sessionDemo);
    if isfile(sessionFile)
        delete(sessionFile);
    end
    appS = mps.App('Visible', 'off');
    appS.loadFile(sessionDemo);
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    kOriginal = appS.Params(ki).value;
    appS.setParam('k', 8);
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, '8'), ...
        'setParam should update k');
    assert(isfile(sessionFile), 'session file should be written after edits');
    appS.undoLastEdit();
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, kOriginal), ...
        'undo should restore the original k');
    appS.redoLastEdit();
    ki = find(strcmp({appS.Params.name}, 'k'), 1);
    assert(strcmp(appS.Params(ki).newValue, '8'), ...
        'redo should reapply k=8');
    delete(appS);

    appS2 = mps.App('Visible', 'off');
    appS2.loadFile(sessionDemo);
    ki = find(strcmp({appS2.Params.name}, 'k'), 1);
    assert(strcmp(appS2.Params(ki).newValue, '8'), ...
        'session should restore the unsaved k value');
    delete(appS2);
    if isfile(sessionFile)
        delete(sessionFile);
    end
    delete(sessionDemo);
    fprintf('  undo/redo + session: ok\n');

    % --- 19. Diff preview + source stamp ---------------------------------
    stamp1 = mps.sourceStamp(demo);
    diffText = mps.textDiff( ...
        sprintf('a = 1;\nb = 2;\n'), sprintf('a = 3;\nb = 2;\n'));
    assert(any(strncmp(diffText, '- ', 2)), 'diff should contain a removed line');
    assert(any(strncmp(diffText, '+ ', 2)), 'diff should contain an added line');
    dlgDiff = mps.DiffDialog('test', diffText, 'Visible', 'off');
    dlgDiff.confirm();
    assert(dlgDiff.Result, 'diff dialog confirm should set Result');
    delete(dlgDiff);
    dlgDiff2 = mps.DiffDialog('test', diffText, 'Visible', 'off');
    dlgDiff2.cancel();
    assert(~dlgDiff2.Result, 'diff dialog cancel should clear Result');
    delete(dlgDiff2);

    stampFile = fullfile(tempdir, 'mps_stamp_test.m');
    fid = fopen(stampFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 1;\n');
    fclose(fid);
    stamp2 = mps.sourceStamp(stampFile);
    fid = fopen(stampFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = 2;\n');
    fclose(fid);
    stamp3 = mps.sourceStamp(stampFile);
    assert(~mps.sameSourceStamp(stamp2, stamp3), ...
        'source stamp should detect a changed file');
    assert(mps.sameSourceStamp(stamp1, mps.sourceStamp(demo)), ...
        'source stamp should be stable for an unchanged file');
    delete(stampFile);
    fprintf('  diff preview + source stamp: ok\n');

    % --- 20. RunExecutor -------------------------------------------------
    execDemo = fullfile(tempdir, 'mps_executor_demo.m');
    copyfile(demo, execDemo);
    pExec = mps.scan(execDemo);
    for k = 1:numel(pExec)
        if strcmp(pExec(k).name, 'k')
            pExec(k).newValue = '8';
            pExec(k).use = true;
        end
    end
    ex = mps.RunExecutor(execDemo, pExec, false);
    ex.Progress = @(msg) [];
    execOut = ex.run();
    assert(execOut.run.ok, 'RunExecutor run failed');
    assert(abs(execOut.run.workspaceData.k - 8) < 1e-12, ...
        'RunExecutor should apply k=8');
    assert(isfile(execOut.reportPath), 'RunExecutor report missing');
    execRoot = fullfile(fileparts(execDemo), 'parameter_studio_runs');
    if isfolder(execRoot)
        rmdir(execRoot, 's');
    end
    delete(execDemo);
    fprintf('  run executor: ok\n');

    % --- 20b. Project entry execution -----------------------------------
    projectRoot = fullfile(tempdir, 'mps_project_runner_test');
    if isfolder(projectRoot)
        rmdir(projectRoot, 's');
    end
    mkdir(projectRoot);
    fid = fopen(fullfile(projectRoot, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nc.bias=2;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(projectRoot, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, ['c=config(); y=c.gain*10; ' ...
        'figure(''Name'',''project''); plot(1:3);\n']);
    fclose(fid);
    pProj = mps.scan(fullfile(projectRoot, 'config.m'));
    gi = find(strcmp({pProj.name}, 'c.gain'), 1);
    pProj(gi).newValue = '5';
    pProj(gi).use = true;
    projExec = mps.ProjectRunExecutor( ...
        fullfile(projectRoot, 'config.m'), ...
        fullfile(projectRoot, 'entry.m'), pProj, false);
    projExec.Progress = @(msg) [];
    projOut = projExec.run();
    assert(projOut.run.ok, 'ProjectRunExecutor failed');
    assert(abs(projOut.run.workspaceData.y - 50) < 1e-12, ...
        'project entry should use the tuned config');
    assert(isfile(projOut.reportPath), 'project report missing');
    rmdir(projectRoot, 's');
    fprintf('  project entry execution: ok\n');

    % --- 21. SweepRunner -------------------------------------------------
    sweepDemo = fullfile(tempdir, 'mps_sweep_runner_demo.m');
    copyfile(demo, sweepDemo);
    pRun = mps.scan(sweepDemo);
    kiRun = find(strcmp({pRun.name}, 'k'), 1);
    runner = mps.SweepRunner(sweepDemo, pRun, kiRun, {[4 8]}, ...
        true, 't', {'y'}, false);
    runner.Progress = @(fraction, message) [];
    sweepOut = runner.run();
    assert(sweepOut.ok, 'SweepRunner failed');
    assert(sweepOut.count == 2, 'SweepRunner should run two scenarios');
    assert(isfile(sweepOut.report), 'SweepRunner report missing');
    assert(isfile(sweepOut.metricsPath), 'SweepRunner metrics CSV missing');
    assert(isfile(sweepOut.overlayPath), 'SweepRunner overlay missing');
    sweepRootOut = fullfile(fileparts(sweepDemo), 'parameter_studio_runs');
    if isfolder(sweepRootOut)
        rmdir(sweepRootOut, 's');
    end
    delete(sweepDemo);
    fprintf('  sweep runner: ok\n');

    if license('test', 'Distrib_Computing_Toolbox')
        parallelDemo = fullfile(tempdir, 'mps_sweep_parallel_demo.m');
        copyfile(demo, parallelDemo);
        pPar = mps.scan(parallelDemo);
        kiPar = find(strcmp({pPar.name}, 'k'), 1);
        runnerPar = mps.SweepRunner(parallelDemo, pPar, kiPar, ...
            {[4 8]}, true, 't', {'y'}, false);
        runnerPar.Parallel = true;
        runnerPar.Progress = @(fraction, message) [];
        parOut = runnerPar.run();
        assert(parOut.ok, 'parallel sweep failed');
        assert(parOut.count == 2, 'parallel sweep should run two scenarios');
        assert(isfile(parOut.report), 'parallel sweep report missing');
        assert(isfile(parOut.metricsPath), 'parallel sweep metrics missing');
        parRoot = fullfile(fileparts(parallelDemo), 'parameter_studio_runs');
        if isfolder(parRoot)
            rmdir(parRoot, 's');
        end
        delete(parallelDemo);

        bgDemo = fullfile(tempdir, 'mps_background_demo.m');
        copyfile(demo, bgDemo);
        pBg = mps.scan(bgDemo);
        pool = gcp('nocreate');
        future = parfeval(pool, @mps.backgroundRun, 1, ...
            bgDemo, pBg, 100, 512);
        bgOut = fetchOutputs(future);
        assert(bgOut.run.ok, 'backgroundRun failed');
        assert(isfile(bgOut.reportPath), 'background report missing');
        bgRoot = fullfile(fileparts(bgDemo), 'parameter_studio_runs');
        if isfolder(bgRoot)
            rmdir(bgRoot, 's');
        end
        delete(bgDemo);
        fprintf('  parallel sweep + background run: ok\n');
    end

    % --- 22. Interactive-call detection + sweep cancel -------------------
    interactiveFile = fullfile(tempdir, 'mps_interactive_test.m');
    fid = fopen(interactiveFile, 'w', 'n', 'UTF-8');
    fprintf(fid, ['%% input(''fake'');\n' ...
        's = ''input(''ignored'')'';\n' ...
        'answer = input(''value? '');\n' ...
        'pause(0.1);\n' ...
        'keyboard;\n']);
    fclose(fid);
    calls = mps.detectInteractiveCalls(interactiveFile);
    names = {calls.name};
    assert(any(strcmp(names, 'input')), 'input() should be detected');
    assert(any(strcmp(names, 'pause')), 'pause() should be detected');
    assert(any(strcmp(names, 'keyboard')), 'keyboard should be detected');
    assert(sum(strcmp(names, 'input')) == 1, ...
        'commented/string input calls should be ignored');
    delete(interactiveFile);

    sweepDemo2 = fullfile(tempdir, 'mps_sweep_cancel_demo.m');
    copyfile(demo, sweepDemo2);
    pCancel = mps.scan(sweepDemo2);
    kiCancel = find(strcmp({pCancel.name}, 'k'), 1);
    runnerCancel = mps.SweepRunner(sweepDemo2, pCancel, kiCancel, ...
        {[4 8]}, false, '', {}, false);
    runnerCancel.ShouldCancel = @() true;
    cancelOut = runnerCancel.run();
    assert(cancelOut.canceled, 'sweep runner should report cancellation');
    assert(cancelOut.count == 0, 'cancelled sweep should run no scenarios');
    cancelRoot = fullfile(fileparts(sweepDemo2), 'parameter_studio_runs');
    if isfolder(cancelRoot)
        rmdir(cancelRoot, 's');
    end
    delete(sweepDemo2);
    fprintf('  interactive detection + sweep cancel: ok\n');

    % --- 23. App UI construction -----------------------------------------
    app = mps.App('Visible', 'off');
    app.loadFile(demo);
    assert(~isempty(app.Params), 'app should load the demo parameters');
    ki = find(strcmp({app.Params.name}, 'k'), 1);
    app.toggleLock('k');
    assert(app.Params(ki).locked, 'public toggleLock should lock k');
    app.toggleLock('k');
    assert(~app.Params(ki).locked, 'public toggleLock should unlock k');
    app.Params(1).description = '测试注释';
    app.clearAnnotations();
    assert(isempty(app.Params(1).description), ...
        'clearAnnotations should clear descriptions');

    manualLoad = fullfile(tempdir, 'mps_manual_load.m');
    copyfile(demo, manualLoad);
    pLoad = mps.scan(manualLoad);
    pLoad = [pLoad, mps.makeManualParam(manualLoad, 'gain', '3')];
    mps.writeManualParams(manualLoad, pLoad);
    app.loadFile(manualLoad);
    assert(any(strcmp({app.Params.name}, 'gain')), ...
        'loadFile should restore manual parameters');

    uiProject = fullfile(tempdir, 'mps_ui_project_test');
    if isfolder(uiProject)
        rmdir(uiProject, 's');
    end
    mkdir(uiProject);
    fid = fopen(fullfile(uiProject, 'config.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'function c=config()\nc.gain=1;\nend\n');
    fclose(fid);
    fid = fopen(fullfile(uiProject, 'entry.m'), 'w', 'n', 'UTF-8');
    fprintf(fid, 'c=config(); y=c.gain*2;\n');
    fclose(fid);
    app.loadFile(fullfile(uiProject, 'config.m'));
    app.setEntryPoint(fullfile(uiProject, 'entry.m'));
    app.runCurrent();
    assert(~isempty(app.Results.LastReport), ...
        'project entry run should create a report');
    rmdir(uiProject, 's');
    delete(app);
    if isfile(mps.sessionPath(manualLoad))
        delete(mps.sessionPath(manualLoad));
    end
    if isfile(mps.manualParamsPath(manualLoad))
        delete(mps.manualParamsPath(manualLoad));
    end
    delete(manualLoad);
    if isfile(mps.sessionPath(demo))
        delete(mps.sessionPath(demo));
    end
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
