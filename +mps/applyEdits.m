function [outText, applied] = applyEdits(sourceFile, params, outputPath, varargin)
%APPLYEDITS Write a copy of a script with selected numeric literals replaced.
%
%   [text, applied] = mps.applyEdits(sourceFile, params)
%   [text, applied] = mps.applyEdits(sourceFile, params, outputPath, ...)
%
%   params is the struct array returned by mps.scan, after the app/user has
%   updated newValue and use.
%
%   Name/value options:
%       'NeutralizeCloseAll'  default false.  When true, standalone
%                             "close all" statements are commented out in the
%                             generated copy so figures survive for capture.
%       'Footer'              default ''.  Text appended as a comment block
%                             (used when saving a tuned .m for the user).
%
%   Only literals whose use=true and whose newValue differs from value are
%   changed.  Edits are applied right-to-left on each line, so several
%   values on the same line (e.g. a struct constructor) work.

    neutralize = false;
    footer = '';
    for k = 1:2:numel(varargin)
        if k + 1 > numel(varargin), break; end
        switch lower(char(varargin{k}))
            case 'neutralizecloseall'
                neutralize = logical(varargin{k+1});
            case 'footer'
                footer = char(varargin{k+1});
        end
    end

    if ~isfile(sourceFile)
        error('mps:applyEdits:fileNotFound', mps.tr( ...
            '找不到文件：%s', 'File not found: %s'), sourceFile);
    end

    raw = fileread(sourceFile);
    raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
    raw = strrep(raw, sprintf('\r'), sprintf('\n'));
    lines = regexp(raw, '\n', 'split');
    trailingNewline = false;
    if ~isempty(lines) && isempty(lines{end})
        lines(end) = [];
        trailingNewline = true;
    end

    edits = struct('line', {}, 'start', {}, 'end', {}, 'text', {}, ...
        'name', {}, 'old', {});
    applied = struct('name', {}, 'old', {}, 'new', {}, 'line', {});

    for k = 1:numel(params)
        p = params(k);
        if ~isfield(p, 'use') || ~p.use, continue; end
        if isfield(p, 'locked') && p.locked, continue; end
        if isfield(p, 'manual') && logical(p.manual), continue; end
        oldText = strtrim(p.value);
        newText = strtrim(p.newValue);
        if strcmp(oldText, newText), continue; end
        if isempty(newText)
            warning('mps:applyEdits:emptyValue', mps.tr( ...
                '参数 %s 的新值为空，已跳过。', ...
                'Parameter %s has an empty new value; skipped.'), p.name);
            continue;
        end
        [okValue, ~] = mps.validateValue(newText);
        if ~okValue
            warning('mps:applyEdits:badValue', mps.tr( ...
                '参数 %s 的新值不是安全的数值表达式，已跳过：%s', ...
                'New value for parameter %s is not a safe numeric expression; skipped: %s'), ...
                p.name, newText);
            continue;
        end
        edits(end+1) = struct('line', p.line, 'start', p.colStart, ...
            'end', p.colEnd, 'text', newText, 'name', p.name, ...
            'old', oldText); %#ok<AGROW>
        applied(end+1) = struct('name', p.name, 'old', oldText, ...
            'new', newText, 'line', p.line); %#ok<AGROW>
    end

    % User-added parameters are prepended as assignments.  They have no
    % source position, so they cannot participate in the literal edits.
    manualLines = {};
    for k = 1:numel(params)
        p = params(k);
        if ~isfield(p, 'manual') || ~logical(p.manual)
            continue;
        end
        if ~isfield(p, 'use') || ~p.use
            continue;
        end
        value = strtrim(char(p.newValue));
        if isfield(p, 'locked') && p.locked
            value = strtrim(char(p.value));
        end
        if isempty(value) || ~isvarname(p.name)
            continue;
        end
        [ok, ~] = mps.validateValue(value);
        if ~ok
            continue;
        end
        manualLines{end+1} = sprintf('%s = %s;', p.name, value); %#ok<AGROW>
        applied(end+1) = struct('name', p.name, 'old', p.value, ...
            'new', value, 'line', 0); %#ok<AGROW>
    end

    % Apply from the end of the file backwards so line/column positions stay
    % valid.  Within a line, apply right-to-left.
    if ~isempty(edits)
        [~, order] = sortrows([[edits.line]', -[edits.start]'], [1 2]);
        edits = edits(order);
        for k = 1:numel(edits)
            e = edits(k);
            if e.line < 1 || e.line > numel(lines), continue; end
            line = lines{e.line};
            s = e.start;
            t = e.end;
            if s < 1 || t > numel(line) || s > t
                warning('mps:applyEdits:badRange', mps.tr( ...
                    '参数 %s 的位置超出范围，已跳过。', ...
                    'Position for parameter %s is out of range; skipped.'), ...
                    e.name);
                continue;
            end
            lines{e.line} = [line(1:s-1), e.text, line(t+1:end)];
        end
    end

    if neutralize
        for k = 1:numel(lines)
            lines{k} = neutralizeCloseAll(lines{k});
        end
    end

    outText = strjoin(lines, sprintf('\n'));
    if trailingNewline
        outText = [outText, sprintf('\n')];
    end
    if ~isempty(manualLines)
        prefix = [strjoin(manualLines, sprintf('\n')), sprintf('\n')];
        outText = [prefix, outText];
    end
    if ~isempty(footer)
        if ~isempty(outText) && outText(end) ~= sprintf('\n')
            outText = [outText, sprintf('\n')];
        end
        outText = [outText, footer];
        if isempty(footer) || footer(end) ~= sprintf('\n')
            outText = [outText, sprintf('\n')];
        end
    end

    if nargin >= 3 && ~isempty(outputPath)
        parent = fileparts(outputPath);
        if ~isempty(parent) && ~isfolder(parent)
            mkdir(parent);
        end
        fid = fopen(outputPath, 'w', 'n', 'UTF-8');
        if fid < 0
            error('mps:applyEdits:cannotWrite', mps.tr( ...
                '无法写入：%s', 'Cannot write: %s'), outputPath);
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', outText);
    end
end

% -------------------------------------------------------------------------
function line = neutralizeCloseAll(line)
%NEUTRALIZECLOSEALL Replace close all with a harmless expression.
%   This keeps figures available for capture.  Strings and comments are
%   left untouched.
    code = codeOnly(line);
    pat = '(?<![A-Za-z0-9_])close\s+all(\s+(force|hidden))?(?![A-Za-z0-9_])';
    [starts, ends] = regexp(code, pat, 'start', 'end');
    for k = numel(starts):-1:1
        if starts(k) < 1 || ends(k) > numel(line), continue; end
        line = [line(1:starts(k)-1), '1', line(ends(k)+1:end)];
    end
end

% -------------------------------------------------------------------------
function code = codeOnly(line)
%CODEONLY Blank out comments and string contents, keeping positions.
    n = numel(line);
    mask = true(1, n);
    i = 1;
    while i <= n
        c = line(i);
        if c == '%'
            mask(i:n) = false;
            break;
        elseif c == '.' && i + 2 <= n && line(i+1) == '.' && line(i+2) == '.'
            mask(i:n) = false;
            break;
        elseif c == '"'
            j = i + 1;
            while j <= n
                if line(j) == '"'
                    if j < n && line(j+1) == '"'
                        j = j + 2;
                        continue;
                    end
                    break;
                end
                j = j + 1;
            end
            mask(i:min(j, n)) = false;
            i = j + 1;
        elseif c == ''''
            p = i - 1;
            while p >= 1 && isspace(line(p)), p = p - 1; end
            transpose = false;
            if p >= 1
                pc = line(p);
                % A preceding quote does NOT make this a transpose: 'a' 'b'
                % concatenates two strings.  Only 'a).' is a transpose.
                transpose = isletter(pc) || (pc >= '0' && pc <= '9') || pc == '_' || ...
                    pc == ')' || pc == ']' || pc == '}' || pc == '.';
            end
            if transpose
                i = i + 1;
            else
                j = i + 1;
                while j <= n
                    if line(j) == ''''
                        if j < n && line(j+1) == ''''
                            j = j + 2;
                            continue;
                        end
                        break;
                    end
                    j = j + 1;
                end
                mask(i:min(j, n)) = false;
                i = j + 1;
            end
        else
            i = i + 1;
        end
    end
    code = line;
    code(~mask) = ' ';
end
