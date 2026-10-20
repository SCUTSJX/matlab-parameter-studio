function path = manualParamsPath(sourceFile)
%MANUALPARAMSPATH Sidecar for user-added parameters.

    [folder, base] = fileparts(char(sourceFile));
    path = fullfile(folder, [base '_manual.json']);
end
