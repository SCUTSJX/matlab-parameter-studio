function jsonPath = writeAnnotationTemplate(sourceFile, params, jsonPath)
%WRITEANNOTATIONTEMPLATE Export a JSON file for AI / manual annotation.
%
%   jsonPath = mps.writeAnnotationTemplate(sourceFile, params)
%   jsonPath = mps.writeAnnotationTemplate(sourceFile, params, jsonPath)
%
%   The generated file contains one entry per scanned parameter with its
%   name, current value, line number, category and a few lines of source
%   context.  Give the file to an AI assistant (or fill it in yourself) and
%   ask it to complete "description" (Chinese meaning / physics) and "unit"
%   for every entry.  Then use the app's "导入注释" button, or call
%   mps.readAnnotations + mps.applyAnnotations.
%
%   The "id" field must not be changed: it is the exact position of the
%   literal in the file and is used for precise matching.

    if nargin < 3 || isempty(jsonPath)
        [folder, base] = fileparts(sourceFile);
        jsonPath = fullfile(folder, [base '_annotations.json']);
    end

    raw = fileread(sourceFile);
    raw = strrep(raw, sprintf('\r\n'), sprintf('\n'));
    raw = strrep(raw, sprintf('\r'), sprintf('\n'));
    lines = regexp(raw, '\n', 'split');
    if ~isempty(lines) && isempty(lines{end})
        lines(end) = [];
    end

    entries = struct('id', {}, 'name', {}, 'value', {}, 'line', {}, ...
        'category', {}, 'note', {}, 'context', {}, ...
        'contextBefore', {}, 'contextAfter', {}, ...
        'description', {}, 'unit', {});
    for k = 1:numel(params)
        p = params(k);
        if ~isfield(p, 'description'), p.description = ''; end
        if ~isfield(p, 'unit'), p.unit = ''; end
        e = struct();
        e.id = p.id;
        e.name = p.name;
        e.value = p.value;
        e.line = p.line;
        e.category = p.category;
        e.note = p.note;
        e.context = p.context;
        e.contextBefore = contextLines(lines, p.line, -2, -1);
        e.contextAfter = contextLines(lines, p.line, 1, 2);
        e.description = p.description;
        e.unit = p.unit;
        entries(end+1) = e; %#ok<AGROW>
    end

    out = struct();
    out.schema = 'mps.annotations.v1';
    out.sourceFile = sourceFile;
    out.created = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    out.parameterCount = numel(entries);
    out.instructions = [ ...
        '请为 parameters 里的每个参数填写 description（中文含义/物理意义）' ...
        '和 unit（单位，可留空）。不要修改 id、name、line。description ' ...
        '请结合 context、contextBefore、contextAfter、note 和 value 判断；' ...
        '如果无法确定，请写“待确认”并说明原因。返回完整的 JSON。'];
    out.parameters = entries;

    txt = '';
    try
        txt = jsonencode(out, 'PrettyPrint', true);
    catch
        txt = jsonencode(out);
    end

    fid = fopen(jsonPath, 'w', 'n', 'UTF-8');
    if fid < 0
        error('mps:writeAnnotationTemplate:cannotWrite', ...
            '无法写入：%s', jsonPath);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', txt);
end

% -------------------------------------------------------------------------
function c = contextLines(lines, lineNo, fromOffset, toOffset)
    a = max(1, lineNo + fromOffset);
    b = min(numel(lines), lineNo + toOffset);
    c = {};
    for k = a:b
        txt = lines{k};
        if numel(txt) > 200
            txt = [txt(1:197), '...'];
        end
        c{end+1} = txt; %#ok<AGROW>
    end
end
