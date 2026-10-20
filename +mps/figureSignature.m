function signature = figureSignature(fig)
%FIGURESIGNATURE Cheap content fingerprint for an existing figure.
%
%   Run scripts may reuse an existing figure (figure(1); clf; plot(...)).
%   Comparing signatures before/after the run lets runScript capture those
%   figures without capturing unrelated user windows.

    signature = 'error';
    if isempty(fig) || ~isvalid(fig)
        return;
    end
    parts = {};
    try
        parts{end+1} = sprintf('fig|%s|%s|%s', ...
            safeNumber(get(fig, 'Number')), ...
            safeString(get(fig, 'Name')), ...
            safeColor(get(fig, 'Color')));
        axesList = findall(fig, 'Type', 'axes');
        for a = 1:numel(axesList)
            ax = axesList(a);
            parts{end+1} = sprintf('ax|%s|%s|%s|%s|%s', ...
                safeColor(get(ax, 'Color')), ...
                safeVector(get(ax, 'XLim')), ...
                safeVector(get(ax, 'YLim')), ...
                safeString(axTitle(ax)), ...
                safeString(get(ax, 'Tag'))); %#ok<AGROW>
            children = findall(ax);
            for c = 1:numel(children)
                h = children(c);
                type = get(h, 'Type');
                switch type
                    case 'line'
                        parts{end+1} = sprintf('line|%s|%s|%s|%s', ...
                            safeVector(get(h, 'XData')), ...
                            safeVector(get(h, 'YData')), ...
                            safeColor(get(h, 'Color')), ...
                            safeString(get(h, 'DisplayName'))); %#ok<AGROW>
                    case 'patch'
                        parts{end+1} = sprintf('patch|%s|%s|%s', ...
                            safeVector(get(h, 'XData')), ...
                            safeVector(get(h, 'YData')), ...
                            safeColor(get(h, 'FaceColor'))); %#ok<AGROW>
                    case 'image'
                        cdata = get(h, 'CData');
                        parts{end+1} = sprintf('image|%s|%s', ...
                            safeVector(cdata), safeVector(get(h, 'XData'))); %#ok<AGROW>
                    case 'text'
                        parts{end+1} = sprintf('text|%s|%s|%s', ...
                            safeString(get(h, 'String')), ...
                            safeVector(get(h, 'Position')), ...
                            safeString(get(h, 'Tag'))); %#ok<AGROW>
                    case 'legend'
                        parts{end+1} = sprintf('legend|%s', ...
                            safeString(get(h, 'String'))); %#ok<AGROW>
                    otherwise
                        parts{end+1} = sprintf('%s|%s|%s', type, ...
                            safeString(get(h, 'Tag')), ...
                            safeVector(get(h, 'Position'))); %#ok<AGROW>
                end
            end
        end
        signature = strjoin(parts, ';');
    catch
        signature = 'error';
    end
end

% -------------------------------------------------------------------------
function s = safeNumber(v)
    if isnumeric(v) && isscalar(v)
        s = num2str(v, '%.10g');
    else
        s = '';
    end
end

% -------------------------------------------------------------------------
function s = safeString(v)
    try
        if iscell(v)
            v = strjoin(cellfun(@char, v, 'UniformOutput', false), '|');
        elseif isstring(v)
            v = strjoin(cellstr(v), '|');
        end
        if ischar(v)
            s = v;
        else
            s = '';
        end
    catch
        s = '';
    end
end

% -------------------------------------------------------------------------
function s = safeVector(v)
    if isempty(v)
        s = 'empty';
        return;
    end
    try
        nums = double(v(:));
        nums = nums(~isnan(nums));
        if isempty(nums)
            s = 'nan';
        else
            s = sprintf('%d:%.10g:%.10g:%.10g', numel(nums), ...
                sum(abs(nums)), nums(1), nums(end));
        end
    catch
        s = 'nonnumeric';
    end
end

% -------------------------------------------------------------------------
function s = safeColor(v)
    if isnumeric(v) && numel(v) <= 4
        s = sprintf('%.4g,', double(v(:)));
    elseif ischar(v)
        s = v;
    else
        s = '';
    end
end

% -------------------------------------------------------------------------
function s = axTitle(ax)
    s = '';
    try
        t = get(ax, 'Title');
        if ~isempty(t) && isvalid(t)
            s = safeString(get(t, 'String'));
        end
    catch
    end
end
