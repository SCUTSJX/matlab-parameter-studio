function writeManualParams(sourceFile, params)
%WRITEMANUALPARAMS Persist user-added parameters next to the script.

    path = mps.manualParamsPath(sourceFile);
    manual = struct([]);
    for k = 1:numel(params)
        if isfield(params, 'manual') && logical(params(k).manual)
            manual = [manual, params(k)]; %#ok<AGROW>
        end
    end
    try
        if isempty(manual)
            if isfile(path)
                delete(path);
            end
            return;
        end
        fid = fopen(path, 'w', 'n', 'UTF-8');
        if fid < 0
            return;
        end
        fprintf(fid, '%s', jsonencode(manual));
        fclose(fid);
    catch
    end
end
