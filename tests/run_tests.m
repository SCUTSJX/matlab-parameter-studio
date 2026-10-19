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

    % --- 9. Function file detection --------------------------------------
    funcFile = fullfile(tempdir, 'mps_func_test.m');
    fid = fopen(funcFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'function y=f(x)\ny=x+1;\nend\n');
    fclose(fid);
    p4 = mps.scan(funcFile);
    assert(~isempty(p4), 'function bodies should still be scanned');

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
