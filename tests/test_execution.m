% test_execution tests. Executed in the run_tests workspace.

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

    lazyDir = fullfile(tempdir, 'mps_lazy_run');
    if isfolder(lazyDir)
        rmdir(lazyDir, 's');
    end
    rLazy = mps.runScript(demo, scriptPath, lazyDir, ...
        'LazyWorkspaceMB', 0);
    assert(rLazy.ok, rLazy.error);
    assert(~isempty(rLazy.matFile) && isfile(rLazy.matFile), ...
        'lazy run should save workspace.mat');
    assert(isempty(fieldnames(rLazy.workspaceData)), ...
        'lazy run should not copy the full workspace into memory');
    assert(any(strcmp({rLazy.workspace.name}, 'k')), ...
        'lazy run should still return a workspace summary');
    SLazy = load(rLazy.matFile, 'k');
    assert(abs(SLazy.k - 8) < 1e-12, ...
        'lazy workspace.mat should contain the run result');
    fprintf('  lazy workspace: ok\n');

    errVarScript = fullfile(tempdir, 'mps_err_variable.m');
    fid = fopen(errVarScript, 'w', 'n', 'UTF-8');
    fprintf(fid, 'err = 42;\nx = 1;\n');
    fclose(fid);
    errVarDir = fullfile(tempdir, 'mps_err_variable_run');
    if isfolder(errVarDir)
        rmdir(errVarDir, 's');
    end
    rErrVar = mps.runScript(errVarScript, errVarScript, errVarDir);
    assert(rErrVar.ok, rErrVar.error);
    assert(isfield(rErrVar.workspaceData, 'err') && ...
        rErrVar.workspaceData.err == 42, ...
        'a user variable named err must not be filtered out');
    rmdir(errVarDir, 's');
    delete(errVarScript);
    fprintf('  user err variable capture: ok\n');

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
