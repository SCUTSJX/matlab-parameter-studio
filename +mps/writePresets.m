function writePresets(sourceFile, presets)
%WRITEPRESETS Save named parameter sets next to a script.
%
%   mps.writePresets(sourceFile, presets)
%
%   presets is the struct array returned by mps.readPresets (or modified by
%   the app).  The file is <script>_presets.json.

    p = mps.presetsPath(sourceFile);
    out = struct();
    out.schema = 'mps.presets.v1';
    out.sourceFile = char(sourceFile);
    out.saved = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    out.presets = presets;

    if isempty(presets)
        % Keep an empty but valid file so the app can remember the deletion.
        out.presets = struct('name', {}, 'created', {}, 'note', {}, 'values', {});
    end

    txt = '';
    try
        txt = jsonencode(out, 'PrettyPrint', true);
    catch
        txt = jsonencode(out);
    end

    fid = fopen(p, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:writePresets:cannotWrite', '无法写入参数集文件：%s', p);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', txt);
end
