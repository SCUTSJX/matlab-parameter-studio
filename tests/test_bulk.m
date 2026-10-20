% test_bulk tests. Executed in the run_tests workspace.

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
