function value = language(newValue)
%LANGUAGE Get or set the UI language for MATLAB Parameter Studio.
%
%   lang = mps.language()          % 'zh' (default) or 'en'
%   mps.language('en')             % switch user-visible text to English
%   mps.language('zh')             % switch back to Chinese
%
%   The setting is process-wide and is used by mps.tr at call time.
%   It does not change identifiers, JSON keys, file names or report data.

    persistent current
    if isempty(current)
        current = 'zh';
    end
    if nargin >= 1 && ~isempty(newValue)
        candidate = lower(char(newValue));
        if ~any(strcmp(candidate, {'zh', 'en'}))
            error('mps:language:unsupported', ...
                'Unsupported language: %s (use ''zh'' or ''en'').', ...
                char(newValue));
        end
        current = candidate;
    end
    value = current;
end
