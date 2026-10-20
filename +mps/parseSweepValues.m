function [values, err] = parseSweepValues(txt)
%PARSESWEEPVALUES Parse a sweep value list.
%
%   [values, err] = mps.parseSweepValues('1, 2, 4')
%   [values, err] = mps.parseSweepValues('1:0.5:5')
%   [values, err] = mps.parseSweepValues('0.5 0.75 1')
%
%   Supported: comma / semicolon / whitespace separated numbers or
%   expressions, and colon ranges such as 1:2:9.  Empty text returns [].
%   On error, err contains a message and values is [].

    values = [];
    err = '';
    if isempty(txt)
        return;
    end
    txt = strtrim(char(txt));
    if isempty(txt)
        return;
    end

    tokens = regexp(txt, '[,\s;]+', 'split');
    tokens = tokens(~cellfun(@isempty, tokens));
    if isempty(tokens)
        return;
    end

    out = [];
    for k = 1:numel(tokens)
        tok = tokens{k};
        [ok, v] = mps.validateValue(tok);
        if ~ok || isempty(v)
            err = mps.tr('无法解析扫描值：%s', ...
                'Cannot parse sweep value: %s', tok);
            values = [];
            return;
        end
        if numel(v) > 200
            err = mps.tr('单个扫描值的元素太多（%d）：%s', ...
                'Too many elements in a single sweep value (%d): %s', ...
                numel(v), tok);
            values = [];
            return;
        end
        out = [out, v(:)']; %#ok<AGROW>
    end
    values = out;
end
