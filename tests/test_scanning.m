% test_scanning tests. Executed in the run_tests workspace.

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

    % --- 13b. Bracket signs and quoted strings ---------------------------
    signFile = fullfile(tempdir, 'mps_sign_scan.m');
    fid = fopen(signFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 'a = [1 -1];\nb = [1-1];\nc = [1 - 1];\n');
    fclose(fid);
    pSign = mps.scan(signFile);
    v1 = {pSign([pSign.line] == 1).value};
    v2 = {pSign([pSign.line] == 2).value};
    v3 = {pSign([pSign.line] == 3).value};
    assert(any(strcmp(v1, '-1')), ...
        'space-separated bracket element should keep its unary sign');
    assert(~any(strcmp(v2, '-1')), ...
        '[1-1] is binary subtraction, not two elements');
    assert(~any(strcmp(v3, '-1')), ...
        '[1 - 1] is binary subtraction, not two elements');
    delete(signFile);

    quoteFile = fullfile(tempdir, 'mps_quote_scan.m');
    fid = fopen(quoteFile, 'w', 'n', 'UTF-8');
    fprintf(fid, 's = ''a'' ''1'';\n');
    fclose(fid);
    pQuote = mps.scan(quoteFile);
    assert(~any(strcmp({pQuote.value}, '1')), ...
        'numeric text inside a quoted string must not become a parameter');
    delete(quoteFile);
    fprintf('  bracket sign + quote scanning: ok\n');
