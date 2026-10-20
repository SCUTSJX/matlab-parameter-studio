function logWarning(context, err, varargin)
%LOGWARNING Record a non-fatal failure and warn once per unique message.
%
%   mps.logWarning(context, err)
%   mps.logWarning(context, err, 'Silent', true)
%
%   Empty catch blocks on user-visible paths should call this instead of
%   swallowing the failure.  Pure cleanup catches can stay silent.

    silent = false;
    for k = 1:2:numel(varargin)
        if k + 1 <= numel(varargin) && ...
                strcmpi(char(varargin{k}), 'Silent')
            silent = logical(varargin{k+1});
        end
    end

    if isa(err, 'MException')
        message = err.message;
        identifier = err.identifier;
    elseif isstruct(err) && isfield(err, 'message')
        message = err.message;
        identifier = '';
    else
        message = char(err);
        identifier = '';
    end
    message = strtrim(message);
    if isempty(message)
        message = '未知错误';
    end

    % Avoid repeating the same warning dozens of times in a sweep.
    persistent seen
    if isempty(seen)
        seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end
    key = [char(context) '|' message];
    first = ~isKey(seen, key);
    if first
        seen(key) = true;
    end

    if first && ~silent
        try
            warning('mps:logWarning', '%s：%s', char(context), message);
        catch
            % 避免日志失败递归调用自身
        end
    end

    try
        logFile = fullfile(tempdir, 'matlab_parameter_studio.log');
        fid = fopen(logFile, 'a', 'n', 'UTF-8');
        if fid >= 0
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, '[%s] %s', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                char(context));
            if ~isempty(identifier)
                fprintf(fid, ' [%s]', identifier);
            end
            fprintf(fid, ': %s\n', message);
        end
    catch
        % 日志写入失败时不再递归记录
    end
end
