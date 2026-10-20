function calls = detectInteractiveCalls(filePath)
%DETECTINTERACTIVECALLS Find calls that can make a script wait for input.
%
%   calls = mps.detectInteractiveCalls(filePath)
%
%   Returns a struct array with fields name and line.  Strings, comments
%   and block comments are ignored.  The check is intentionally heuristic:
%   it catches input/keyboard/pause and common dialog/ginput calls before
%   the app blocks on them.

    calls = struct('name', {}, 'line', {});
    if isempty(filePath) || ~isfile(filePath)
        return;
    end
    lines = splitlines(fileread(filePath));
    inBlock = false;
    callNames = {'input', 'pause', 'uiwait', 'waitfor', 'ginput', ...
        'questdlg', 'menu'};

    for k = 1:numel(lines)
        line = lines{k};
        trimmed = strtrim(line);
        if inBlock
            if startsWith(trimmed, '%}')
                inBlock = false;
            end
            continue;
        end
        if startsWith(trimmed, '%{')
            inBlock = true;
            continue;
        end

        % Remove strings and comments before looking for identifiers.
        code = regexprep(line, '''[^'']*''', '''''');
        code = regexprep(code, '"[^"]*"', '""');
        pct = find(code == '%', 1);
        if ~isempty(pct)
            code = code(1:pct-1);
        end

        if ~isempty(regexp(code, ...
                '(?<![A-Za-z0-9_])keyboard(?![A-Za-z0-9_])', 'once'))
            calls(end+1) = struct('name', 'keyboard', 'line', k); %#ok<AGROW>
        end
        for c = 1:numel(callNames)
            name = callNames{c};
            pat = sprintf('(?<![A-Za-z0-9_])%s\\s*\\(', name);
            if ~isempty(regexp(code, pat, 'once'))
                calls(end+1) = struct('name', name, 'line', k); %#ok<AGROW>
            end
        end
    end
end
