% test_detection tests. Executed in the run_tests workspace.

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

    % --- 7b. Invalid preset values and malformed sidecars -----------------
    pBad = mps.scan(demo);
    badPreset = struct('name', 'bad', 'values', struct( ...
        'id', '', 'name', 'k', 'line', 7, ...
        'newValue', '1; system(''calc'')', 'use', true, 'locked', false));
    [pBadApplied, badStats] = mps.applyPreset(pBad, badPreset);
    assert(badStats.invalid == 1, 'unsafe preset value should be invalid');
    ki = find(strcmp({pBadApplied.name}, 'k'), 1);
    assert(strcmp(pBadApplied(ki).newValue, pBadApplied(ki).value), ...
        'invalid preset value must keep the original value');

    robustFile = fullfile(tempdir, 'mps_robust_sidecars.m');
    copyfile(demo, robustFile);
    fid = fopen(mps.presetsPath(robustFile), 'w', 'n', 'UTF-8');
    fprintf(fid, ['{"presets":[{"name":"ok","values":' ...
        '[{"name":"k","newValue":"8"}]},123]}']);
    fclose(fid);
    robustPresets = mps.readPresets(robustFile);
    assert(numel(robustPresets) == 1, ...
        'mixed-type preset arrays should keep valid entries');

    fid = fopen(mps.sessionPath(robustFile), 'w', 'n', 'UTF-8');
    fprintf(fid, ['{"values":[{"name":"k","newValue":"8"},123]}']);
    fclose(fid);
    robustSession = mps.readSession(robustFile);
    assert(~isempty(robustSession) && numel(robustSession.values) == 1, ...
        'mixed-type session arrays should keep valid entries');

    fid = fopen(mps.manualParamsPath(robustFile), 'w', 'n', 'UTF-8');
    fprintf(fid, ['[{"name":"gain","newValue":"3","use":true},123]']);
    fclose(fid);
    robustManual = mps.readManualParams(robustFile);
    assert(numel(robustManual) == 1, ...
        'mixed-type manual arrays should keep valid entries');
    delete(mps.presetsPath(robustFile));
    delete(mps.sessionPath(robustFile));
    delete(mps.manualParamsPath(robustFile));
    delete(robustFile);
    fprintf('  invalid presets + malformed sidecars: ok\n');
