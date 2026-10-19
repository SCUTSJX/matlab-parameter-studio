function path = sessionPath(sourceFile)
%SESSIONPATH Sidecar file used to restore unsaved table edits.

    [folder, base] = fileparts(char(sourceFile));
    path = fullfile(folder, [base '_session.json']);
end
