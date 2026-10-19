function [ok, value] = validateValue(txt)
%VALIDATEVALUE Check that a user-entered parameter is a safe numeric expression.
%
%   [ok, value] = mps.validateValue('2*pi')
%
%   The function deliberately rejects identifiers other than pi, Inf, NaN,
%   true, false, i and j.  This prevents a parameter field from executing
%   arbitrary functions while still allowing common numeric expressions.

    ok = false;
    value = [];
    if isempty(txt)
        ok = true;
        return;
    end
    txt = strtrim(char(txt));
    if isempty(txt)
        ok = true;
        return;
    end
    if any(txt == sprintf('\n')) || any(txt == sprintf('\r')) || ...
            contains(txt, ';') || contains(txt, '%')
        return;
    end

    % Remove numeric literals (including exponents) before looking for
    % identifiers, so "1e-3" does not look like the identifier "e".
    letters = regexprep(txt, '\d+(\.\d*)?([eE][+\-]?\d+)?', '');
    ids = regexp(letters, '[A-Za-z_]\w*', 'match');
    allowed = {'pi', 'Inf', 'inf', 'NaN', 'nan', 'true', 'false', 'i', 'j'};
    for k = 1:numel(ids)
        if ~any(strcmp(ids{k}, allowed))
            return;
        end
    end

    % Only allow characters that can appear in a numeric expression/array.
    if isempty(regexp(txt, '^[\d\s\.\,\;\:\+\-\*\/\^\(\)\[\]\{\}eEiIjJpPInNaTruFals]+$', 'once'))
        return;
    end

    try
        value = eval(txt); %#ok<EVLEXTX>
        ok = isnumeric(value) || islogical(value);
    catch
        ok = false;
        value = [];
    end
end
