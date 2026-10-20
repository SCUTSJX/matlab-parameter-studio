function tf = isNoneLabel(value)
%ISNONELABEL True for the language-independent "(none)" placeholder.
%
%   mps.isNoneLabel(value) accepts the Chinese '(无)' sentinel, the English
%   '(None)' / '(none)' sentinels and an empty value.  Worker processes may
%   run with a different mps.language setting than the client, so runtime
%   comparisons should not depend on mps.tr here.

    if isempty(value)
        tf = true;
        return;
    end
    if iscell(value)
        value = value{1};
    end
    if isstring(value)
        value = char(value);
    end
    if ~ischar(value)
        tf = false;
        return;
    end
    tf = any(strcmp(value, {'(无)', '(None)', '(none)'}));
end
