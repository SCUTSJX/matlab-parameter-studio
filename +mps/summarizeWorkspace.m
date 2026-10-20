function ws = summarizeWorkspace(S)
%SUMMARIZEWORKSPACE Turn a workspace struct into rows for the app/report.
%
%   ws = mps.summarizeWorkspace(S) returns a struct array with fields
%   name, class, size, min, max, preview.

    ws = struct('name', {}, 'class', {}, 'size', {}, 'min', {}, ...
        'max', {}, 'preview', {});
    if isempty(S) || ~isstruct(S)
        return;
    end

    names = sort(fieldnames(S));
    for k = 1:numel(names)
        name = names{k};
        try
            v = S.(name);
        catch
            continue;
        end

        sz = size(v);
        szStr = sizeString(sz);
        cls = class(v);
        mn = [];
        mx = [];
        preview = '';

        if isnumeric(v) || islogical(v)
            if ~isempty(v)
                try
                    if numel(v) <= 5e6
                        mn = min(v(:));
                        mx = max(v(:));
                    else
                        % Avoid materializing a full column copy for big arrays.
                        mn = min(v, [], 'all');
                        mx = max(v, [], 'all');
                    end
                catch
                end
            end
            if isscalar(v)
                preview = num2str(v);
            elseif isvector(v) && numel(v) <= 8
                preview = mat2str(v);
            else
                preview = sprintf('%s %s', szStr, cls);
            end
        elseif ischar(v) || isstring(v)
            if isstring(v) && ~isscalar(v)
                preview = sprintf('string [%s]', szStr);
            else
                preview = char(v);
                if numel(preview) > 80
                    preview = [preview(1:77), '...'];
                end
                preview = strrep(preview, sprintf('\n'), ' ');
                preview = strrep(preview, sprintf('\r'), ' ');
            end
        elseif isstruct(v)
            preview = sprintf('struct (%d fields)', numel(fieldnames(v)));
        elseif iscell(v)
            preview = sprintf('cell {%s}', szStr);
        elseif isa(v, 'function_handle')
            preview = func2str(v);
            if numel(preview) > 80
                preview = [preview(1:77), '...'];
            end
        else
            preview = cls;
        end

        ws(end+1) = struct('name', name, 'class', cls, 'size', szStr, ...
            'min', mn, 'max', mx, 'preview', preview); %#ok<AGROW>
    end
end

% -------------------------------------------------------------------------
function s = sizeString(sz)
    parts = arrayfun(@(x) num2str(x), sz, 'UniformOutput', false);
    s = strjoin(parts, 'x');
end
