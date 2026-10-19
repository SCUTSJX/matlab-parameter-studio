function stamp = sourceStamp(filePath)
%SOURCESTAMP Cheap fingerprint for detecting external file edits.
%
%   stamp = mps.sourceStamp(filePath)
%
%   Uses the modification time, byte size and character count.  This is
%   deliberately cheap enough to call before every run/save, while still
%   catching normal editor saves.  A changed byte count catches edits that
%   happen within the file system's timestamp resolution.

    filePath = char(filePath);
    info = dir(filePath);
    if isempty(info)
        error('mps:sourceStamp:missingFile', '文件不存在：%s', filePath);
    end
    text = fileread(filePath);
    codes = double(text);
    stamp = struct( ...
        'file', filePath, ...
        'datenum', info(1).datenum, ...
        'bytes', info(1).bytes, ...
        'chars', numel(text), ...
        'checksum', sum(codes), ...
        'weightedChecksum', sum(codes .* (1:numel(codes))));
end
