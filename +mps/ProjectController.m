classdef ProjectController < handle
    %PROJECTCONTROLLER Open a project entry script and populate App state.
    %
    %   App keeps loadProject / setEntryPoint as thin aliases.  UI handles
    %   that are private to App are supplied through Ctx.

    properties
        Ctx
    end

    methods
        function obj = ProjectController(ctx)
            obj.Ctx = ctx;
        end

        function load(obj, entryFile)
            obj.loadInternal(entryFile);
        end

        function setEntryPoint(obj, entryFile)
            obj.setEntryPointInternal(entryFile);
        end

        function onOpen(obj)
            app = obj.Ctx.App;
            if isempty(app.SourceFile)
                startDir = pwd;
            else
                startDir = fileparts(app.SourceFile);
            end
            [file, path] = uigetfile({ ...
                '*.m', mps.tr('项目入口脚本 (*.m)', ...
                'Project entry script (*.m)')}, ...
                mps.tr('选择项目入口脚本', 'Select project entry script'), ...
                startDir);
            if isequal(file, 0)
                return;
            end
            obj.load(fullfile(path, file));
        end

        function onChooseEntry(obj)
            app = obj.Ctx.App;
            if isempty(app.SourceFile)
                uialert(app.UIFigure, ...
                    mps.tr('请先打开一个 .m 文件。', ...
                    'Open a .m file first.'), ...
                    mps.tr('没有文件', 'No file'), 'Icon', 'warning');
                return;
            end
            [file, path] = uigetfile({ ...
                '*.m', mps.tr('MATLAB 脚本 (*.m)', ...
                'MATLAB script (*.m)')}, ...
                mps.tr('选择项目入口脚本', 'Select project entry script'), ...
                fileparts(app.SourceFile));
            if isequal(file, 0)
                return;
            end
            obj.setEntryPoint(fullfile(path, file));
        end
    end

    methods (Access = private)
        function loadInternal(obj, entryFile)
            %LOADINTERNAL Scan all .m files under the entry folder.
            app = obj.Ctx.App;
            ctx = obj.Ctx;
            session = mps.ProjectSession.load(entryFile);
            if ~session.ok
                uialert(app.UIFigure, session.error, ...
                    mps.tr('打开项目失败', 'Failed to open project'), ...
                    'Icon', 'error');
                return;
            end
            entryFile = session.entryFile;
            p = session.params;
            app.SourceFile = entryFile;
            app.EntryFile = entryFile;
            app.ProjectRoot = session.projectRoot;
            app.ProjectMode = true;
            app.ProjectStamp = session.projectStamp;
            app.IsFunctionFile = false;
            app.SourceLines = session.lines;
            app.Params = p;
            app.LastAnnotations = struct([]);
            app.AnnotationFile = '';
            app.SourceStamp = session.sourceStamp;
            ctx.TableCtl.setSource(entryFile, app.SourceStamp);
            ctx.TableCtl.RecommendedMinScore = 5;
            ctx.TableCtl.resetHistory();
            ctx.PresetCtl.loadFromDisk();
            ctx.Results.clear();
            ctx.TableCtl.clearSelection();
            ctx.SourcePreview.Value = {''};
            ctx.LogArea.Value = {''};
            ctx.FileLabel.Text = entryFile;
            ctx.FileLabel.FontColor = [0.12 0.12 0.12];
            ctx.FileLabel.Tooltip = entryFile;
            ctx.RescanButton.Enable = 'on';
            ctx.RunButton.Enable = 'on';
            ctx.SaveButton.Enable = 'off';
            ctx.ExportButton.Enable = 'on';
            ctx.SweepButton.Enable = 'on';
            ctx.ManualButton.Enable = 'off';
            ctx.EntryButton.Enable = 'on';
            ctx.AnnotateTemplateButton.Enable = 'on';
            ctx.ImportAnnotationButton.Enable = 'on';
            ctx.ClearAnnotationButton.Enable = 'on';
            ctx.LockButton.Enable = 'on';
            ctx.BulkButton.Enable = 'on';
            ctx.CompareButton.Enable = 'on';
            if license('test', 'Distrib_Computing_Toolbox')
                ctx.BackgroundCheck.Enable = 'on';
            else
                ctx.BackgroundCheck.Enable = 'off';
            end
            ctx.ReportButton.Enable = 'off';
            ctx.FolderButton.Enable = 'off';
            ctx.CloseFiguresButton.Enable = 'off';
            ctx.PlotButton.Enable = 'off';
            ctx.SavePlotButton.Enable = 'off';
            ctx.ExportCsvButton.Enable = 'off';
            ctx.RefreshFcn();
            labels = ctx.FileFilterDrop.Items(2:end);
            defaultLabel = mps.ProjectSession.defaultFilter(labels);
            if ~isempty(defaultLabel)
                ctx.FileFilterDrop.Value = defaultLabel;
                ctx.RefreshFcn();
            end
            ctx.StatusLabel.Text = mps.tr( ...
                ['项目模式：入口 %s，扫描 %d 个 .m 文件，识别 %d 个参数。' ...
                 '默认显示 %s，可切换“文件”筛选。'], ...
                ['Project mode: entry %s, scanned %d .m files, ' ...
                 'found %d parameters. Showing %s by default; switch ' ...
                 'with the "File" filter.'], ...
                entryFile, numel(unique({p.sourceFile})), numel(p), ...
                ctx.FileFilterDrop.Value);
            drawnow;
        end

        function setEntryPointInternal(obj, entryFile)
            %SETENTRYPOINTINTERNAL Run entry script with edits from SourceFile.
            app = obj.Ctx.App;
            ctx = obj.Ctx;
            entryFile = char(entryFile);
            if ~isfile(entryFile)
                error('mps:App:missingEntry', ...
                    mps.tr('入口脚本不存在：%s', ...
                        'Entry script not found: %s', entryFile));
            end
            app.EntryFile = entryFile;
            ctx.RunButton.Enable = 'on';
            if license('test', 'Distrib_Computing_Toolbox')
                ctx.BackgroundCheck.Enable = 'on';
            end
            ctx.StatusLabel.Text = mps.tr( ...
                '项目入口：%s（运行时会复制项目到临时目录并应用参数）', ...
                ['Project entry: %s (a run copies the project to a ' ...
                 'temporary folder and applies the parameters)'], ...
                entryFile);
        end
    end
end
