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

    % --- 6. Function file detection --------------------------------------
    funcFile = fullfile(tempdir, 'mps_func_test.m');
    fid = fopen(funcFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'function y=f(x)\ny=x+1;\nend\n');
    fclose(fid);
    p4 = mps.scan(funcFile);
    assert(~isempty(p4), 'function bodies should still be scanned');

    fprintf('ALL TESTS PASSED\n');
end
