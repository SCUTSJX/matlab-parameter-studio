function params = scan(filePath, varargin)
%SCAN Find editable numeric values in a MATLAB .m file.
%
%   params = mps.scan(filePath) returns a struct array describing every
%   numeric (and logical) literal that appears in executable code.  The
%   scanner is deliberately heuristic: it cannot know which numbers are
%   physical parameters and which are plot styling, array sizes, indexes,
%   etc.  It therefore assigns each literal a name, a category and a
%   recommendation score.  The app shows recommended values by default and
%   lets the user reveal/edit every literal.
%
%   Optional name/value pairs:
%       'MinScore'   default 3   score at/above which Use=true
%       'MaxParams'  default 2000
%
%   Returned fields:
%       id, name, value, newValue, line, colStart, colEnd, score,
%       category, note, context, use, isChanged, sourceFile, literalIndex
%
%   The scanner only handles .m text files.  It does not execute code.

    minScore = 3;
    maxParams = 2000;
    for k = 1:2:numel(varargin)
        if k + 1 > numel(varargin), break; end
        switch lower(char(varargin{k}))
            case 'minscore'
                minScore = varargin{k+1};
            case 'maxparams'
                maxParams = varargin{k+1};
        end
    end

    if ~isfile(filePath)
        error('mps:scan:fileNotFound', '找不到文件：%s', filePath);
    end
    [~, ~, ext] = fileparts(filePath);
    if ~strcmpi(ext, '.m')
        error('mps:scan:unsupportedFile', '目前只支持 .m 文件，收到：%s', ext);
    end

    raw = fileread(filePath);
    raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
    raw = strrep(raw, sprintf('\r'), sprintf('\n'));
    lines = regexp(raw, '\n', 'split');
    if ~isempty(lines) && isempty(lines{end})
        lines(end) = [];
    end

    params = emptyParams();
    inBlockComment = false;
    lastComment = '';
    lastCommentLine = -10;

    % Precompute trailing comments for every physical line.
    lineComments = cell(numel(lines), 1);
    for ck = 1:numel(lines)
        [~, cpos] = maskLine(lines{ck});
        txt = lines{ck};
        if cpos > 0
            if cpos + 2 <= numel(txt) && strcmp(txt(cpos:cpos+2), '...')
                % A continuation may still carry a trailing % comment.
                pct = find(txt(cpos:end) == '%', 1);
                if isempty(pct)
                    lineComments{ck} = '';
                else
                    lineComments{ck} = strtrim(txt(cpos+pct:end));
                end
            else
                lineComments{ck} = strtrim(txt(cpos+1:end));
            end
        else
            lineComments{ck} = '';
        end
    end

    li = 1;
    while li <= numel(lines)
        line = lines{li};
        trimmed = strtrim(line);

        if inBlockComment
            if startsWith(trimmed, '%}')
                inBlockComment = false;
            end
            li = li + 1;
            continue;
        end
        if startsWith(trimmed, '%{')
            inBlockComment = true;
            li = li + 1;
            continue;
        end

        % A comment-only line is remembered as a possible description for
        % the next parameter line.
        if ~isempty(trimmed) && trimmed(1) == '%'
            lastComment = regexprep(trimmed, '^%+\s*', '');
            lastCommentLine = li;
            li = li + 1;
            continue;
        end

        % Join continuation lines ("...") into one logical line, keeping a
        % position map back to the physical file so edits still work.
        logical = line;
        mapLine = repmat(li, 1, numel(line));
        mapCol = 1:numel(line);
        cur = li;
        while cur < numel(lines) && hasContinuation(logical)
            nxt = lines{cur+1};
            [~, cstart] = maskLine(logical);
            if cstart > 0 && cstart + 2 <= numel(logical) && ...
                    strcmp(logical(cstart:cstart+2), '...')
                logical(cstart:end) = ' ';
            end
            logical = [logical, ' ', nxt]; %#ok<AGROW>
            mapLine = [mapLine, cur, repmat(cur+1, 1, numel(nxt))]; %#ok<AGROW>
            mapCol = [mapCol, numel(lines{cur})+1, 1:numel(nxt)]; %#ok<AGROW>
            cur = cur + 1;
        end
        li = cur + 1;

        [codeMask, ~] = maskLine(logical);
        code = logical;
        code(~codeMask) = ' ';
        lits = findLiterals(logical, codeMask);
        if isempty(lits)
            if li - lastCommentLine > 2
                lastComment = '';
            end
            continue;
        end

        assignments = parseAssignments(logical, code);
        structMap = parseStructFields(logical, code, lits, assignments);

        for k = 1:numel(lits)
            lit = lits(k);
            pl = mapLine(lit.start);
            pEndLine = mapLine(lit.end);
            if pl ~= pEndLine
                continue; % a value cannot span physical lines here
            end
            pcStart = mapCol(lit.start);
            pcEnd = mapCol(lit.end);
            context = strtrim(lines{pl});
            if ~isempty(lineComments{pl})
                note = lineComments{pl};
            elseif pl - lastCommentLine <= 2
                note = lastComment;
            else
                note = '';
            end

            p = struct();
            p.id = sprintf('%s|%d|%d', filePath, pl, pcStart);
            p.name = '';
            p.value = lit.text;
            p.newValue = lit.text;
            p.line = pl;
            p.colStart = pcStart;
            p.colEnd = pcEnd;
            p.score = 0;
            p.category = 'literal';
            p.note = note;
            p.context = context;
            p.use = false;
            p.isChanged = false;
            p.sourceFile = filePath;
            p.literalIndex = k;
            p.isLogical = lit.isLogical;
            p.description = '';
            p.unit = '';
            p.locked = false;
            p.ignored = false;
            p.manual = false;

            % --- 1. Struct field names are the strongest signal. ---------
            if isKey(structMap, lit.start)
                info = structMap(lit.start);
                p.name = info.name;
                p.category = 'struct';
                p.score = 7;
            else
                % --- 2. Assignment context. ------------------------------
                a = assignmentAt(assignments, lit.start);
                if ~isempty(a)
                    p = nameFromAssignment(p, a, lit, lits, code);
                else
                    % --- 3. Function argument / index context. -----------
                    [callName, isCall] = enclosingCall(code, lit.start);
                    if isCall
                        p.category = callCategory(callName);
                        p.name = sprintf('%s 参数', callName);
                        p.score = 0;
                        if ismember(p.category, {'style','layout','size','index','control'})
                            p.score = -6;
                        end
                        fieldName = precedingFieldName(logical, lit.start);
                        if ~isempty(fieldName)
                            p.name = fieldName;
                            p.score = max(p.score, 2);
                            if ismember(p.category, {'style','layout'})
                                p.score = -4;
                            end
                        end
                    else
                        p.name = sprintf('第 %d 行数字 %d', pl, k);
                        p.category = 'literal';
                        p.score = 0;
                    end
                end
            end

            % --- 4. Descriptions and parameter-like names help. ----------
            if ~isempty(note)
                p.score = p.score + 1;
            end
            if ~isempty(p.name) && isParameterLikeName(p.name)
                p.score = p.score + 1;
            end
            if strcmp(p.category, 'control')
                p.score = p.score - 2;
            end
            if lit.isLogical
                p.score = max(p.score, 2);
            end

            % --- 5. Explicit % @param annotations always win. ------------
            annotated = contains(note, '@param') || ...
                (pl - lastCommentLine <= 2 && contains(lastComment, '@param'));
            if annotated
                p.category = 'annotated';
                p.score = max(p.score, 9);
                p.name = regexprep(p.name, '^@param\s*', '');
            end

            % % @ignore suppresses a literal from the recommended list and
            % from runs; it still appears in the "全部数字" view.
            ignored = contains(note, '@ignore') || ...
                (pl - lastCommentLine <= 2 && contains(lastComment, '@ignore'));
            if ignored
                p.ignored = true;
                p.category = 'ignored';
                p.score = -Inf;
                p.use = false;
            else
                p.use = p.score >= minScore && ~ismember(p.category, ...
                    {'style','layout','size','index','control'});
            end
            p.isChanged = false;

            params(end+1) = p; %#ok<AGROW>
            if numel(params) >= maxParams
                return;
            end
        end

        if li - lastCommentLine > 2
            lastComment = '';
        end
    end
end

% -------------------------------------------------------------------------
function p = emptyParams()
    p = struct('id', {}, 'name', {}, 'value', {}, 'newValue', {}, ...
        'line', {}, 'colStart', {}, 'colEnd', {}, 'score', {}, ...
        'category', {}, 'note', {}, 'context', {}, 'use', {}, ...
        'isChanged', {}, 'sourceFile', {}, 'literalIndex', {}, ...
        'isLogical', {}, 'description', {}, 'unit', {}, 'locked', {}, ...
        'ignored', {}, 'manual', {});
end

% -------------------------------------------------------------------------
function [mask, commentStart] = maskLine(line)
%MASKLINE Mark executable characters.  Strings and comments become false.
    n = numel(line);
    mask = true(1, n);
    commentStart = 0;
    i = 1;
    while i <= n
        c = line(i);
        if c == '%'
            mask(i:n) = false;
            commentStart = i;
            return;
        elseif c == '.' && i + 2 <= n && line(i+1) == '.' && line(i+2) == '.'
            mask(i:n) = false;
            commentStart = i;
            return;
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
            if isTransposeQuote(line, i)
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
end

% -------------------------------------------------------------------------
function tf = isTransposeQuote(line, i)
    p = i - 1;
    while p >= 1 && isspace(line(p))
        p = p - 1;
    end
    if p < 1
        tf = false;
        return;
    end
    c = line(p);
    % Note: a preceding quote does NOT make this a transpose.  In 'a' 'b'
    % the second quote opens a new string (implicit concatenation); the
    % only valid transpose after a string is the dotted 'a'.'
    tf = isletter(c) || isDigitChar(c) || c == '_' || c == ')' || ...
        c == ']' || c == '}' || c == '.';
end

% -------------------------------------------------------------------------
function lits = findLiterals(line, mask)
%FINDLITERALS Find number and logical literals outside strings/comments.
    n = numel(line);
    code = line;
    code(~mask) = ' ';
    lits = struct('start', {}, 'end', {}, 'text', {}, 'isLogical', {});

    % Track []/{} nesting depth at each position (code only).  Inside
    % concatenation brackets MATLAB treats a sign that touches its number
    % as unary: [1 -1] is the two elements 1 and -1, while [1 - 1] and
    % [1-1] are binary subtraction.  Outside brackets the sign is always
    % binary unless preceded by an operator.
    depth = zeros(1, n);
    d = 0;
    for k = 1:n
        if mask(k)
            c = line(k);
            if c == '[' || c == '{'
                d = d + 1;
            elseif c == ']' || c == '}'
                d = max(0, d - 1);
            end
        end
        depth(k) = d;
    end

    % Logical literals.
    for word = {'true', 'false'}
        w = word{1};
        pos = regexp(code, ['(?<![A-Za-z0-9_])' w '(?![A-Za-z0-9_])'], 'start');
        for q = 1:numel(pos)
            s = pos(q);
            e = s + numel(w) - 1;
            if all(mask(s:e))
                lits(end+1) = struct('start', s, 'end', e, ...
                    'text', w, 'isLogical', true); %#ok<AGROW>
            end
        end
    end

    % Numeric literals.
    i = 1;
    while i <= n
        if ~mask(i)
            i = i + 1;
            continue;
        end
        c = line(i);

        if isletter(c) || c == '_'
            while i <= n && (isletter(line(i)) || isDigitChar(line(i)) || line(i) == '_')
                i = i + 1;
            end
            continue;
        end

        startsNumber = isDigitChar(c) || (c == '.' && i < n && isDigitChar(line(i+1)));
        if ~startsNumber
            i = i + 1;
            continue;
        end

        % Do not start in the middle of an identifier or an existing number.
        if i > 1
            prev = line(i-1);
            if isletter(prev) || isDigitChar(prev) || prev == '_' || prev == '.'
                i = i + 1;
                continue;
            end
        end

        j = i;
        while j <= n && isDigitChar(line(j))
            j = j + 1;
        end
        if j <= n && line(j) == '.'
            j = j + 1;
            while j <= n && isDigitChar(line(j))
                j = j + 1;
            end
        end
        if j <= n && (line(j) == 'e' || line(j) == 'E')
            k = j + 1;
            if k <= n && (line(k) == '+' || line(k) == '-')
                k = k + 1;
            end
            if k <= n && isDigitChar(line(k))
                j = k;
                while j <= n && isDigitChar(line(j))
                    j = j + 1;
                end
            end
        end
        % Complex suffix (1i, 2.5j).
        if j <= n && (line(j) == 'i' || line(j) == 'j')
            if j == n || ~(isletter(line(j+1)) || isDigitChar(line(j+1)) || line(j+1) == '_')
                j = j + 1;
            end
        end
        if j <= n && (isletter(line(j)) || line(j) == '_')
            % e.g. "1st" or "2x": not a numeric literal.
            i = j;
            continue;
        end
        if ~all(mask(i:j-1))
            i = j;
            continue;
        end

        s = i;
        e = j - 1;

        % Include a unary sign in the token so "-1" reads as one value.
        p = s - 1;
        while p >= 1 && isspace(line(p))
            p = p - 1;
        end
        if p >= 1 && (line(p) == '-' || line(p) == '+')
            q = p - 1;
            while q >= 1 && isspace(line(q))
                q = q - 1;
            end
            includeSign = q < 1 || any(line(q) == '([{,;:=+-*/^<>&|~');
            % Inside []/{} concatenation, a sign after whitespace and written
            % directly against the number is unary: [1 -1] -> [1, -1].
            % [1-1] and [1 - 1] remain binary subtraction.
            if ~includeSign && depth(p) > 0 && p > 1 && ...
                    isspace(line(p - 1)) && p + 1 <= n && ...
                    ~isspace(line(p + 1))
                includeSign = true;
            end
            if includeSign
                s = p;
            end
        end

        text = strtrim(line(s:e));
        lits(end+1) = struct('start', s, 'end', e, ...
            'text', text, 'isLogical', false); %#ok<AGROW>
        i = j;
    end

    if ~isempty(lits)
        [~, order] = sort([lits.start]);
        lits = lits(order);
    end
end

% -------------------------------------------------------------------------
function assignments = parseAssignments(line, code)
%PARSEASSIGNMENTS Find "lhs = rhs" statements, including multiple per line.
    assignments = struct('lhs', {}, 'rhsStart', {}, 'rhsEnd', {}, ...
        'stmtStart', {}, 'stmtEnd', {}, 'keyword', {});
    n = numel(line);
    depth = 0;
    stmtStart = 1;
    for i = 1:n
        c = code(i);
        if any(c == '([{')
            depth = depth + 1;
        elseif any(c == ')]}')
            depth = max(0, depth - 1);
        elseif c == ';' && depth == 0
            addStatement(stmtStart, i-1);
            stmtStart = i + 1;
        end
    end
    addStatement(stmtStart, n);

    function addStatement(s, e)
        if e < s, return; end
        txt = strtrim(code(s:e));
        if isempty(txt), return; end
        tok = regexp(txt, '^([A-Za-z]\w*)', 'tokens', 'once');
        kw = '';
        if ~isempty(tok), kw = tok{1}; end
        eq = topLevelEquals(code, s, e);
        if eq == 0, return; end
        lhs = strtrim(code(s:eq-1));
        if isempty(lhs), return; end
        if ~isSimpleLhs(lhs), return; end
        if ismember(lw(kw), {'for','if','while','switch','case','otherwise', ...
                'else','elseif','catch','function','classdef','properties', ...
                'methods','events','enumeration','arguments'})
            return;
        end
        assignments(end+1) = struct('lhs', lhs, 'rhsStart', eq+1, ...
            'rhsEnd', e, 'stmtStart', s, 'stmtEnd', e, 'keyword', kw);
    end
end

% -------------------------------------------------------------------------
function tf = isSimpleLhs(lhs)
    tf = ~isempty(regexp(lhs, '^[A-Za-z]\w*(\.[A-Za-z]\w*)*(\([^()]*\))?$', 'once'));
end

% -------------------------------------------------------------------------
function eq = topLevelEquals(code, s, e)
    depth = 0;
    eq = 0;
    for i = s:e
        c = code(i);
        if any(c == '([{')
            depth = depth + 1;
        elseif any(c == ')]}')
            depth = max(0, depth - 1);
        elseif c == '=' && depth == 0
            prev = 0; next = 0;
            if i > 1, prev = code(i-1); end
            if i < numel(code), next = code(i+1); end
            if next == '=' || any(prev == '=<>~+-*/&|')
                continue;
            end
            eq = i;
            return;
        end
    end
end

% -------------------------------------------------------------------------
function a = assignmentAt(assignments, pos)
    a = [];
    for k = 1:numel(assignments)
        if pos >= assignments(k).rhsStart && pos <= assignments(k).rhsEnd
            a = assignments(k);
            return;
        end
    end
end

% -------------------------------------------------------------------------
function p = nameFromAssignment(p, a, lit, lits, code)
    lhs = a.lhs;
    rhs = strtrim(code(a.rhsStart:a.rhsEnd));

    % Index inside the LHS, e.g. x(1) = 5.
    if lit.start < a.rhsStart
        p.name = sprintf('%s 的索引', lhs);
        p.category = 'index';
        p.score = -5;
        return;
    end

    % Anonymous functions contain code, not a parameter value.
    if ~isempty(rhs) && rhs(1) == '@'
        p.name = sprintf('%s (匿名函数内)', lhs);
        p.category = 'function';
        p.score = -5;
        return;
    end

    inRhs = lits([lits.start] >= a.rhsStart & [lits.end] <= a.rhsEnd);
    idx = find([inRhs.start] == lit.start, 1);
    if isempty(idx), idx = 1; end

    if numel(inRhs) == 1
        % A single literal is usually the assigned value, but not when it
        % is an index or an argument to a function call.
        [callName, isCall] = enclosingCall(code, lit.start);
        if isCall
            cat = callCategory(callName);
            if any(strcmp(cat, {'index','style','layout','size','control'}))
                p.name = sprintf('%s (索引/调用)', lhs);
                p.category = cat;
                p.score = -4;
                return;
            elseif strcmp(cat, 'argument')
                p.name = sprintf('%s (%s 参数)', lhs, callName);
                p.category = 'argument';
                p.score = 1;
                return;
            end
        end
        p.name = lhs;
        p.category = 'assignment';
        p.score = 5;
        return;
    end

    % Ranges such as 0:0.01:10.
    colonPos = topLevelChars(code, a.rhsStart, a.rhsEnd, ':');
    if numel(colonPos) == 2
        if idx == 1
            p.name = sprintf('%s (起点)', lhs);
        elseif idx == 2
            p.name = sprintf('%s (步长)', lhs);
        else
            p.name = sprintf('%s (终点)', lhs);
        end
        p.category = 'range';
        p.score = 3;
        return;
    elseif numel(colonPos) == 1
        if idx == 1
            p.name = sprintf('%s (起点)', lhs);
        else
            p.name = sprintf('%s (终点)', lhs);
        end
        p.category = 'range';
        p.score = 3;
        return;
    end

    rhsTrim = strtrim(rhs);
    if ~isempty(rhsTrim) && rhsTrim(1) == '['
        p.name = sprintf('%s(%d)', lhs, idx);
        p.category = 'array';
        p.score = 2;
    elseif numel(inRhs) > 1
        p.name = sprintf('%s (第 %d 个数字)', lhs, idx);
        p.category = 'expression';
        p.score = 2;
    else
        p.name = lhs;
        p.category = 'assignment';
        p.score = 4;
    end
end

% -------------------------------------------------------------------------
function pos = topLevelChars(code, s, e, ch)
    depth = 0;
    pos = [];
    for i = s:e
        c = code(i);
        if any(c == '([{')
            depth = depth + 1;
        elseif any(c == ')]}')
            depth = max(0, depth - 1);
        elseif c == ch && depth == 0
            pos(end+1) = i; %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------
function map = parseStructFields(line, code, lits, assignments)
%PARSESTRUCTFIELDS Name literals that are values in struct('name', value).
    map = containers.Map('KeyType', 'double', 'ValueType', 'any');
    starts = regexp(code, '(?<![A-Za-z0-9_])struct\s*\(', 'start');
    for k = 1:numel(starts)
        s = starts(k);
        openPos = find(code(s:end) == '(', 1) + s - 1;
        closePos = matchParen(code, openPos);
        if closePos == 0, continue; end

        prefix = '';
        a = assignmentContaining(assignments, s);
        if ~isempty(a) && a.rhsStart <= s
            prefix = a.lhs;
        end
        parseArgs(line, code, lits, openPos+1, closePos-1, prefix, map);
    end
end

% -------------------------------------------------------------------------
function a = assignmentContaining(assignments, pos)
    a = [];
    for k = 1:numel(assignments)
        if pos >= assignments(k).rhsStart && pos <= assignments(k).rhsEnd
            a = assignments(k);
            return;
        end
    end
end

% -------------------------------------------------------------------------
function parseArgs(line, code, lits, s, e, prefix, map)
%PARSEARGS Walk a struct(...) argument list and recurse into nested structs.
    args = splitTopLevel(line, s, e, ',');
    k = 1;
    while k <= numel(args)
        a = args(k);
        txt = strtrim(line(a.start:a.end));
        isName = (numel(txt) >= 2) && ...
            ((txt(1) == '''' && txt(end) == '''') || ...
             (txt(1) == '"' && txt(end) == '"'));
        if isName
            field = txt(2:end-1);
            if k < numel(args)
                v = args(k+1);
                valueTxt = strtrim(line(v.start:v.end));
                full = prefix;
                if isempty(full)
                    full = field;
                else
                    full = sprintf('%s.%s', prefix, field);
                end

                % Nested struct.
                nested = regexp(valueTxt, '^struct\s*\(', 'once');
                if ~isempty(nested)
                    openPos = find(code(v.start:v.end) == '(', 1) + v.start - 1;
                    closePos = matchParen(code, openPos);
                    if closePos > 0
                        parseArgs(line, code, lits, openPos+1, closePos-1, full, map);
                    end
                else
                    % Only simple values get a field name.  A function
                    % call such as csg.noise(...) is not a field value.
                    if isLiteralValue(valueTxt)
                        inside = lits([lits.start] >= v.start & [lits.end] <= v.end);
                        for q = 1:numel(inside)
                            lit = inside(q);
                            if numel(inside) > 1 && numel(valueTxt) > 1 && valueTxt(1) == '['
                                nm = sprintf('%s(%d)', full, q);
                            else
                                nm = full;
                            end
                            % Nested struct calls are visited twice: keep
                            % the longest (most specific) name.
                            if isKey(map, lit.start)
                                old = map(lit.start);
                                if numel(old.name) >= numel(nm)
                                    continue;
                                end
                            end
                            map(lit.start) = struct('name', nm);
                        end
                    end
                end
                k = k + 2;
                continue;
            end
        end
        k = k + 1;
    end
end

% -------------------------------------------------------------------------
function tf = isLiteralValue(txt)
%ISLITERALVALUE True for numbers, arrays, ranges, booleans, not calls.
    t = strtrim(txt);
    if isempty(t), tf = false; return; end
    if strcmp(t, 'true') || strcmp(t, 'false')
        tf = true;
        return;
    end
    tf = ~isempty(regexp(t, '^[+\-]?\s*[\[\]\{\}\d\s\.\,\;\:\+\-\*\/\^\(\)eE]*$', 'once')) ...
        && ~isempty(regexp(t, '\d', 'once'));
end

% -------------------------------------------------------------------------
function closePos = matchParen(code, openPos)
    depth = 0;
    closePos = 0;
    for i = openPos:numel(code)
        c = code(i);
        if c == '(', depth = depth + 1; end
        if c == ')'
            depth = depth - 1;
            if depth == 0
                closePos = i;
                return;
            end
        end
    end
end

% -------------------------------------------------------------------------
function args = splitTopLevel(line, s, e, sep)
%SPLITTOPLEVEL Split a range by a separator outside strings/brackets.
    args = struct('start', {}, 'end', {});
    depth = 0;
    inSingle = false;
    inDouble = false;
    startPos = s;
    i = s;
    while i <= e
        c = line(i);
        if inSingle
            if c == ''''
                if i < e && line(i+1) == ''''
                    i = i + 2;
                    continue;
                end
                inSingle = false;
            end
        elseif inDouble
            if c == '"'
                if i < e && line(i+1) == '"'
                    i = i + 2;
                    continue;
                end
                inDouble = false;
            end
        else
            if c == ''''
                if isTransposeQuote(line, i)
                    % transpose, not a string
                else
                    inSingle = true;
                end
            elseif c == '"'
                inDouble = true;
            elseif any(c == '([{')
                depth = depth + 1;
            elseif any(c == ')]}')
                depth = max(0, depth - 1);
            elseif c == sep && depth == 0
                args(end+1) = struct('start', startPos, 'end', i-1); %#ok<AGROW>
                startPos = i + 1;
            end
        end
        i = i + 1;
    end
    args(end+1) = struct('start', startPos, 'end', e);
end

% -------------------------------------------------------------------------
function [name, isCall] = enclosingCall(code, pos)
%ENCLOSINGCALL Find the innermost function/index call containing pos.
    stack = struct('name', {}, 'open', {});
    i = 1;
    while i < pos
        c = code(i);
        if c == '('
            j = i - 1;
            while j >= 1 && isspace(code(j)), j = j - 1; end
            e = j;
            while j >= 1 && (isletter(code(j)) || isDigitChar(code(j)) || ...
                    code(j) == '_' || code(j) == '.')
                j = j - 1;
            end
            nm = '';
            if e >= j + 1
                nm = code(j+1:e);
            end
            stack(end+1) = struct('name', nm, 'open', i); %#ok<AGROW>
        elseif c == ')'
            if ~isempty(stack)
                stack(end) = [];
            end
        end
        i = i + 1;
    end
    if isempty(stack)
        name = '';
        isCall = false;
    else
        name = stack(end).name;
        isCall = ~isempty(name);
    end
end

% -------------------------------------------------------------------------
function cat = callCategory(name)
    style = {'plot','semilogx','semilogy','loglog','scatter','bar','histogram', ...
        'xlim','ylim','zlim','axis','legend','title','xlabel','ylabel','zlabel', ...
        'text','annotation','set','get','grid','box','hold','subplot','tiledlayout', ...
        'nexttile','colorbar','colormap','shading','view','daspect','pbaspect', ...
        'line','patch','fill','errorbar','stem','stairs','area','contour','surf','mesh'};
    layout = {'figure','uifigure','axes','uiaxes','uitable','uibutton','uilabel', ...
        'uieditfield','uidropdown','uipanel','uigridlayout','uitabgroup','uitab', ...
        'uiprogressdlg','uialert','uiconfirm','inputdlg','msgbox','waitbar'};
    sizeFns = {'zeros','ones','nan','inf','linspace','logspace','cell','repmat', ...
        'reshape','length','size','numel','ndims','sub2ind','ind2sub'};
    known = {'ode45','ode15s','ode23','ode113','ode23s','ode23t','ode23tb', ...
        'sin','cos','tan','asin','acos','atan','atan2','sinh','cosh','tanh', ...
        'exp','log','log10','log2','sqrt','abs','sign','floor','ceil','round', ...
        'max','min','sum','prod','mean','median','std','var','norm','cumsum', ...
        'cumprod','trapz','cumtrapz','gradient','diff','conv','deconv','interp1', ...
        'interp2','polyfit','polyval','roots','fzero','fminsearch','fmincon', ...
        'lsqcurvefit','integral','fft','ifft','filter','tf','ss','step','lsim', ...
        'bode','nyquist','rlocus','margin','feedback','series','parallel','pid', ...
        'pidtune','expm','inv','pinv','det','eig','svd','qr','lu','chol','rank', ...
        'trace','kron','meshgrid','ndgrid','sprintf','fprintf','disp','error', ...
        'warning','num2str','str2double','str2num','mat2str','eval','feval', ...
        'arrayfun','cellfun','rand','randn','rng','tic','toc','now','datestr', ...
        'datenum','datetime','duration','seconds','milliseconds','hours', ...
        'minutes','days','years','isempty','isnumeric','ischar','isstring', ...
        'iscell','isstruct','isfield','fieldnames','rmfield','setfield','getfield', ...
        'struct','cell2mat','mat2cell','num2cell','bsxfun','cat','horzcat', ...
        'vertcat','flip','fliplr','flipud','rot90','permute','squeeze','sort', ...
        'sortrows','unique','ismember','intersect','union','setdiff','setxor', ...
        'any','all','find','nnz','nonzeros','sparse','full','double','single', ...
        'logical','char','string','cellstr','strtrim','strrep','strfind', ...
        'strsplit','strjoin','strcat','strcmp','strcmpi','upper','lower', ...
        'regexp','regexprep','contains','startsWith','endsWith','fullfile', ...
        'fileparts','exist','isfile','isfolder','which','whos'};
    if any(strcmp(name, style))
        cat = 'style';
    elseif any(strcmp(name, layout))
        cat = 'layout';
    elseif any(strcmp(name, sizeFns))
        cat = 'size';
    elseif any(strcmp(name, {'for','while','if','switch','case'}))
        cat = 'control';
    elseif any(strcmp(name, known))
        cat = 'argument';
    else
        % Most likely a variable index such as x(:, 1) or a user function.
        cat = 'index';
    end
end

% -------------------------------------------------------------------------
function name = precedingFieldName(line, pos)
%PRECEDINGFIELDNAME Find a 'Name', value pattern immediately before pos.
    name = '';
    prefix = strtrim(line(1:max(1, pos-1)));
    tok = regexp(prefix, '''([^'']+)''\s*,\s*$', 'tokens', 'once');
    if isempty(tok)
        tok = regexp(prefix, '"([^"]+)"\s*,\s*$', 'tokens', 'once');
    end
    if ~isempty(tok)
        name = tok{1};
    end
end

% -------------------------------------------------------------------------
function tf = isParameterLikeName(name)
    lname = lower(name);
    words = {'mass','stiff','damp','gain','eta','rho','gamma','period', ...
        'amplitude','offset','duration','time','step','dt','tol','seed', ...
        'num','limit','threshold','rate','window','initial','final','max', ...
        'min','k','m','c','x0','v0','kp','ki','kd','alpha','beta','tau', ...
        'freq','omega','sigma','noise','scale','factor','count','n'};
    tf = false;
    for k = 1:numel(words)
        w = words{k};
        if numel(w) <= 2
            if strcmp(lname, w) || ~isempty(regexp(lname, ['(^|[._])' w '($|[._])'], 'once'))
                tf = true; return;
            end
        elseif contains(lname, w)
            tf = true; return;
        end
    end
end

% -------------------------------------------------------------------------
function tf = hasContinuation(text)
%HASCONTINUATION True when the code ends with a "..." continuation.
    [~, cstart] = maskLine(text);
    tf = false;
    if cstart > 0 && cstart + 2 <= numel(text)
        tf = strcmp(text(cstart:cstart+2), '...');
    end
end

% -------------------------------------------------------------------------
function tf = isDigitChar(c)
    tf = c >= '0' && c <= '9';
end

% -------------------------------------------------------------------------
function s = lw(s)
    s = lower(strtrim(s));
end
