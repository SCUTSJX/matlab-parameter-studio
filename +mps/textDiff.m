function lines = textDiff(oldText, newText, context)
%TEXTDIFF Build a compact line diff for the save preview.
%
%   lines = mps.textDiff(oldText, newText)
%   lines = mps.textDiff(oldText, newText, context)
%
%   The generated text uses "-" for lines from the old file, "+" for lines
%   in the saved file and two spaces for unchanged context.  It is intended
%   for the small, line-preserving edits made by applyEdits, not as a
%   general-purpose Myers diff.

    if nargin < 3
        context = 2;
    end
    oldLines = splitLines(oldText);
    newLines = splitLines(newText);
    n = max(numel(oldLines), numel(newLines));
    changed = false(1, n);

    for k = 1:n
        if k > numel(oldLines) || k > numel(newLines)
            changed(k) = true;
        elseif ~strcmp(oldLines{k}, newLines{k})
            changed(k) = true;
        end
    end

    if ~any(changed)
        lines = {mps.tr('没有检测到改动。', 'No changes detected.')};
        return;
    end

    show = changed;
    for k = 1:numel(changed)
        if changed(k)
            lo = max(1, k - context);
            hi = min(n, k + context);
            show(lo:hi) = true;
        end
    end

    lines = {};
    lastShown = 0;
    for k = 1:n
        if ~show(k)
            continue;
        end
        if lastShown > 0 && k > lastShown + 1
            lines{end+1} = '...'; %#ok<AGROW>
        end
        if k > numel(oldLines)
            lines{end+1} = sprintf('+ %4d | %s', k, newLines{k}); %#ok<AGROW>
        elseif k > numel(newLines)
            lines{end+1} = sprintf('- %4d | %s', k, oldLines{k}); %#ok<AGROW>
        elseif ~strcmp(oldLines{k}, newLines{k})
            lines{end+1} = sprintf('- %4d | %s', k, oldLines{k}); %#ok<AGROW>
            lines{end+1} = sprintf('+ %4d | %s', k, newLines{k}); %#ok<AGROW>
        else
            lines{end+1} = sprintf('  %4d | %s', k, oldLines{k}); %#ok<AGROW>
        end
        lastShown = k;
        if numel(lines) >= 600
            lines{end+1} = mps.tr('...（预览已截断）', ...
                '... (preview truncated)'); %#ok<AGROW>
            break;
        end
    end
end

% -------------------------------------------------------------------------
function lines = splitLines(text)
    lines = regexp(char(text), '\r\n|\r|\n', 'split');
    if ~isempty(lines) && isempty(lines{end})
        lines(end) = [];
    end
end
