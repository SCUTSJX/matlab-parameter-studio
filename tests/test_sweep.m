% test_sweep tests. Executed in the run_tests workspace.

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
