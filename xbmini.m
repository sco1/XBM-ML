classdef xbmini < handle & AirdropData
    % XBMINI is a MATLAB class definition providing the user with a set of methods to parse and
    % analyze raw data files output by GCDC XBmini datalogger
    %
    % Initialize an xbmini object using an absolute filepath to the raw log file:
    %
    %     myLog = xbmini(filepath);
    %
    % xbmini methods:
    %     findgroundlevelpressure - Interactively identify ground level pressure
    %     finddescentrate         - Interactively identify payload descent rate
    %     append                  - Append another xbmini object to the end of the current object
    %     fixedwindowtrim         - Interactively trim all loaded data using a fixed time window
    %     windowtrim              - Interactively window and trim all loaded data
    %     save                    - Save xbmini data to a MAT file
    %
    % xbmini static methods:
    %     getdate    - Generate current local timestamp in ISO 8601 format
    %     countlines - Count number of lines in file
    %     windowdata - Interactively window plotted data

    properties
        filepath          % Path to analyzed CSV file
        loggertype        % Type of logger
        analysisdate      % Date of analysis, ISO 8601, yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
        time              % Accelerometer time vector, seconds
        time_temperature  % Temperature time vector, seconds
        time_pressure     % Pressure time vector, seconds
        accel_x           % X acceleration, gees
        accel_y           % Y acceleration, gees
        accel_z           % Z acceleration, gees
        gyro_x            % X gyro (New XBM only)
        gyro_y            % Y gyro (New XBM only)
        gyro_z            % Z gyro (New XBM only)
        quat_w            % W quaternion (New XBM only)
        quat_x            % X quaternion (New XBM only)
        quat_y            % Y quaternion (New XBM only)
        quat_z            % Z quaternion (New XBM only)
        mag_x             % X magnetometer (New XBM only)
        mag_y             % Y magnetometer (New XBM only)
        mag_z             % Z magnetometer (New XBM only)
        pressure          % Raw barometric pressure, pascals
        temperature       % Temperature, Celsius
        altitude_meters   % Pressure altitude, meters, derived from pressure
        altitude_feet     % Pressure altitude, feet, derived from pressure
        descentrate       % Descent rate, feet per second, derived from pressure altitude and pressure time
        allupweight       % All up weight, pounds
    end

    properties (Access = private)
        nlines                          % Number of lines in CSV file
        nheaderlines                    % Number of header lines in CSV file
        ndatapoints                     % Number of data lines in CSV file
        chunksize = 5000;               % Data chunk size for reading in raw data
        countspergee = 2048;            % Raw data counts per gee, for converting accelerometer data
        pressure_groundlevel = 101325;  % Ground level pressure, pascals, default is 101325 Pa
        islegacy                        % Boolean to differentiate between new/old XBmini
        isappended = false              % Boolean to document when another xbmini object has been appended
        defaultwindowlength = 12;       % Default data windowing length, seconds

        appendignoreprops = {'filepath', 'loggertype', 'analysisdate', 'descentrate', 'allupweight'}  % Properties to ignore when appending/trimming
        timeseries = {'time', 'time_temperature', 'time_pressure'};  % These need to be normalized during appending so they're continuous
        pressure_series = {'time_pressure', 'pressure', 'altitude_meters', 'altitude_feet'}  % Data with same timeseries as time_pressure
        temperature_series = {'time_temperature', 'temperature'}  % Data with same timeseries as time_temperature
    end

    methods
        function dataObj = xbmini(filepath)
            % Check to see if a filepath has been passed to xbmini, prompt user to select a file if
            % one hasn't been passed
            if nargin == 1
                filepath = fullfile(filepath);  % Ensure correct file separators
                dataObj.filepath = filepath;
            else
                [file, pathname] = uigetfile('*.csv', 'Select a XB-mini log file (*.csv)');
                dataObj.filepath = [pathname file];
            end

            if ~exist(dataObj.filepath, 'file')
                msgID = 'xbmini:xbmini:InvalidDataPath';
                error(msgID, ...
                      'Path to data file is not valid: %s', dataObj.filepath);
            end

            dataObj.analysisdate = xbmini.getdate;
            dataObj.nlines = xbmini.countlines(dataObj.filepath);

            % Pick appropriate data parser based on logger type
            dataObj.getLoggerType();
            dataObj.count_headerlines();
            dataObj.initializedata();
            if dataObj.islegacy
                dataObj.readrawdata_legacy();
            else
                dataObj.readrawdata();
            end

            dataObj.convertdata();
            dataObj.calcaltitude();
        end

        function findgroundlevelpressure(dataObj)
            % FINDGROUNDLEVELPRESSURE Plots the raw pressure data and prompts the user to window a
            % 30 second region of the plot where the sensor is at ground level. The average pressure
            % from this windowed region is used to update the object's pressure_groundlevel private
            % property. The object's pressure altitude is also recalculated using the updated ground
            % level pressure.
            h.fig = figure;
            h.ax = axes;
            h.ls = plot(h.ax, dataObj.pressure);
            idx = xbmini.fixedwindowdata(h.ls, 30);

            % Calculate and plot average pressure in the windowed region
            dataObj.pressure_groundlevel = mean(dataObj.pressure(idx(1):idx(2)));
            line(idx, ones(2, 1)*dataObj.pressure_groundlevel, 'Color', 'r', 'Parent', h.ax);

            % Recalculate altitudes
            calcaltitude(dataObj);
        end

        function descentrate = finddescentrate(dataObj)
            % FINDDESCENTRATE Plots the pressure altitude (ft) data and prompts the user to window
            % the region over which to calculate the descent rate. The average descent rate (ft/s)
            % is calculated over this windowed region and is used to update the object's descentrate
            % property. descentrate is also an explicit output of this method
            h.fig = figure;
            h.ax = axes;
            h.ls = plot(h.ax, dataObj.altitude_feet);
            idx = xbmini.windowdata(h.ls);

            % Because we just plotted altitude vs. data index, update the plot to altitude vs. time
            % but save the limits and use them so the plot doesn't get zoomed out
            oldxlim = floor(h.ax.XLim);

            % Catch indexing issues if plot isn't zoomed "properly"
            oldxlim(oldxlim < 1) = 1;
            oldxlim(oldxlim > length(dataObj.altitude_feet)) = length(dataObj.altitude_feet);

            oldylim = h.ax.YLim;
            plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', h.ax);
            xlim(h.ax, dataObj.time_pressure(oldxlim));
            ylim(h.ax, oldylim);

            % Calculate and plot linear fit
            myfit = polyfit(dataObj.time_pressure(idx(1):idx(2)), dataObj.altitude_feet(idx(1):idx(2)), 1);
            hold(h.ax, 'on');
            h.fitls = plot(dataObj.time_pressure(idx), polyval(myfit, dataObj.time_pressure(idx)), 'r', 'Parent', h.ax);
            hold(h.ax, 'off');
            xlabel('Time (s)');
            ylabel('Altitude (ft. AGL)');

            %  Add descent rate annotation
            %  Text annotation coordinates are tail to head
            fitmidpointidx = floor(sum(idx)/2);
            fitmidpoint = [dataObj.time_pressure(fitmidpointidx), polyval(myfit, dataObj.time_pressure(fitmidpointidx))];

            annotationx = coord2norm(h.ax, [fitmidpoint(1), fitmidpoint(1)], 0);  % Straight up from midpoint
            annotationtaily = polyval(myfit, dataObj.time_pressure(floor(idx(1) + 0.25*diff(idx))));
            [~, annotationy] = coord2norm(h.ax, 0, [annotationtaily, fitmidpoint(2)]);
            annotationstr = sprintf('SS RoF: %.2f ft/s', abs(myfit(1)));
            annotation(h.fig, 'textarrow', annotationx, annotationy, 'String', annotationstr);

            % Set outputs
            descentrate = myfit(1);
            dataObj.descentrate = descentrate;
        end

        function save(dataObj, varargin)
            % SAVE saves an instance of the xbmini object to a MAT file. File is saved in the same
            % directory as the analyzed log file with the same name as the log.
            %
            % Any existing MAT file of the same name will be overwritten
            p = AirdropData.saveargparse(varargin{:});
            p.FunctionName = 'xbmini:save';

            % Modify the savefilepath if necessary, punt the rest to the super
            if isempty(p.Results.savefilepath)
                if dataObj.isappended
                    [pathname, filename] = fileparts(dataObj.filepath{1});
                    filename = [filename '_appended'];
                else
                    [pathname, filename] = fileparts(dataObj.filepath);
                end

                if p.Results.saveasclass
                    savefilepath = fullfile(pathname, [filename '.mat']);
                else
                    savefilepath = fullfile(pathname, [filename '_noclass.mat']);
                end
            else
                savefilepath = p.Results.savefilepath;
            end

            save@AirdropData(savefilepath, dataObj, p.Results.verboseoutput, p.Results.saveasclass)
        end

        function append(dataObj, inObj)
            % APPEND appends inObj's data to the end of dataObj's data

            % Shift incoming timestamps so we get continuous time vectors instead of a sawtooth
            for ii = 1:numel(dataObj.timeseries)
                offset = dataObj.(dataObj.timeseries{ii})(end);
                inObj.(dataObj.timeseries{ii}) = inObj.(dataObj.timeseries{ii}) + offset;
            end

            % Merge data
            propstoiter = setdiff(properties(dataObj), dataObj.appendignoreprops);
            for ii = 1:numel(propstoiter)
                dataObj.(propstoiter{ii}) = [dataObj.(propstoiter{ii}); inObj.(propstoiter{ii})];
            end

            % Set appended flag for future logic
            dataObj.isappended = true;

            % Append filenames, stash in cell array if one is not already present
            if iscell(dataObj.filepath)
                dataObj.filepath{end+1} = inObj.filepath;
            else
                dataObj.filepath = {dataObj.filepath, inObj.filepath};
            end

            % Update private properties
            dataObj.nlines = dataObj.nlines + inObj.nlines;
            dataObj.ndatapoints = dataObj.ndatapoints + inObj.ndatapoints;
        end

        function windowtrim(dataObj)
            % WINDOWTRIM spawns a new figure window and axes object and plots the xbmini's pressure
            % altitude (feet) vs. time_pressure (seconds)
            %
            % Two draggable lines are generated in the axes object, which the user can drag to
            % specify an arbitrary time window. UIWAITand MSGBOX is used to block MATLAB execution
            % until the user closes the MSGBOX dialog. When execution resumes, the data indices are
            % used to trim all of the appropriate internal data
            fig = figure;
            ax = axes('Parent', fig);
            ls = plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);

            % Call the data windowing helper to obtain data indices.
            idx = dataObj.windowdata(ls);
            trimdata(dataObj, idx);

            % Update the plot with the windowed data
            plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);
        end


        function fixedwindowtrim(dataObj, windowlength)
            % FIXEDWINDOWTRIM spawns a new figure window and axes object and plots the xbmini's
            % pressure altitude (feet) vs. time_pressure (seconds)
            %
            % A draggable fixed window with length, windowlength, in seconds, is generated in the
            % axes object, which the user can drag to choose the time window. If windowlength is not
            % specified, the default value from the object's private properties is used. UIWAIT and
            % MSGBOX is used to block MATLAB execution until the user closes the MSGBOX dialog. When
            % execution resumes, the data indices are used to trim all of the appropriate internal
            % data.
            fig = figure;
            ax = axes('Parent', fig);
            ls = plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);

            % Call the data fixed windowing helper to obtain data indices Check to see if
            % windowlength is provided, if not then we default to the value stored in the object's
            % private properties
            if nargin == 1
                windowlength = dataObj.defaultwindowlength;
            end
            idx = dataObj.fixedwindowdata(ls, windowlength);
            trimdata(dataObj, idx);

            % Update the plot with the windowed data
            plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);
        end


        function [trimmed_objs] = fixedwindowtrim_multi(dataObj, windowlength, n_windows)
            % TODO: Write docstring

            fig = figure;
            ax = axes('Parent', fig);
            ls = plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);

            % Call the data fixed windowing helper to obtain data indices Check to see if
            % windowlength is provided, if not then we default to the value stored in the object's
            % private properties
            if nargin == 1
                windowlength = dataObj.defaultwindowlength;
            end

            trimmed_objs = dataObj.empty(n_windows, 0);
            selected_windows = gobjects(n_windows,1);  % Store handles to selected patches
            for ii = 1:n_windows
                idx = dataObj.fixedwindowdata(ls, windowlength);
                tmp_obj = dataObj.copy();
                trimdata(tmp_obj, idx);
                trimmed_objs(ii) = tmp_obj;

                % Add a patch over already selected regions
                x_selected = ls.XData(idx);
                y_limits = ylim(ax);
                vertices = [
                    x_selected(1), y_limits(1); ...  % Bottom left corner
                    x_selected(2), y_limits(1); ...  % Bottom right corner
                    x_selected(2), y_limits(2); ...  % Top right corner
                    x_selected(1), y_limits(2) ...   % Top left corner
                ];
                selected_windows(ii) = patch( ...
                    'Vertices', vertices, ...
                    'Faces', [1 2 3 4], ...
                    'FaceColor', 'cyan', ...
                    'FaceAlpha', 0.05 ...
                );
            end
        end
    end


    methods (Hidden, Access = protected)
        function getLoggerType(dataObj)
            % Pull logger type from the first line of the data file header
            fID = fopen(dataObj.filepath, 'r');
            tline = fgetl(fID);  % Get first line of data
            fclose(fID);

            if ~ischar(tline)
                msgID = 'xbmini:getLoggerType:InvalidDataFile';
                error(msgID, ...
                      'Invalid header detected, data file may be empty: %s', dataObj.filepath);
            end

            tmp = regexp(tline, '(X16\S*)(?=\,)|(HAM-IMU\+alt)(?=\,)', 'Match');
            dataObj.loggertype = tmp{1};  % De-nest cell
            switch dataObj.loggertype
                case 'X16-B1100-mini'
                    dataObj.islegacy = true;
                case {'X16-ham', 'HAM-IMU+alt'}
                    dataObj.islegacy = false;
                otherwise
                    msgID = 'xbmini:getLoggerType:UnsupportedDevice';
                    error(msgID, ...
                          'Unsupported data logger ''%s'' detected', dataObj.loggertype);
            end
        end


        function count_headerlines(dataObj)
            % Read the data file until we get to a line that doesn't start with a semicolon
            fID = fopen(dataObj.filepath, 'r');
            n_headers = 0;
            while ~feof(fID)
                tline = fgetl(fID);
                if strcmp(tline(1), ';')
                    n_headers = n_headers + 1;
                else
                    break
                end
            end
            fclose(fID);
            dataObj.nheaderlines = n_headers;
        end


        function initializedata(dataObj)
            % Preallocate data arrays based on number of lines in the data file
            dataObj.ndatapoints = dataObj.nlines - dataObj.nheaderlines;
            dataObj.time        = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_x     = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_y     = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_z     = zeros(dataObj.ndatapoints, 1);
            dataObj.pressure    = zeros(dataObj.ndatapoints, 1);
            dataObj.temperature = zeros(dataObj.ndatapoints, 1);

            if ~dataObj.islegacy
                % Initialize fields for new XBM's IMU data
                dataObj.gyro_x = zeros(dataObj.ndatapoints, 1);
                dataObj.gyro_y = zeros(dataObj.ndatapoints, 1);
                dataObj.gyro_z = zeros(dataObj.ndatapoints, 1);
                dataObj.quat_w = zeros(dataObj.ndatapoints, 1);
                dataObj.quat_x = zeros(dataObj.ndatapoints, 1);
                dataObj.quat_y = zeros(dataObj.ndatapoints, 1);
                dataObj.quat_z = zeros(dataObj.ndatapoints, 1);
                dataObj.mag_x  = zeros(dataObj.ndatapoints, 1);
                dataObj.mag_y  = zeros(dataObj.ndatapoints, 1);
                dataObj.mag_z  = zeros(dataObj.ndatapoints, 1);
            end
        end


        function readrawdata_legacy(dataObj)
            % Read raw data from the XBmini
            %
            % Raw data formatting:
            %   Column 1: Time           (seconds, float)
            %   Column 2: X acceleration (counts, integer)
            %   Column 3: Y acceleration (counts, integer)
            %   Column 4: Z acceleration (counts, integer)
            %   Column 5: Pressure       (Pascal, integer)        *Sample rate may be different than accel
            %   Column 6: Temperature    (mill-degree C, integer) *Sample rate may be different than accel

            fID = fopen(dataObj.filepath);
            hlines = dataObj.nheaderlines;
            formatSpec = '%f %d %d %d %d %d';

            step = 1;
            lines_kept = 0;  % Track in case we toss line(s) from the end of the file
            while ~feof(fID)
                segarray = textscan(fID, formatSpec, dataObj.chunksize, ...
                                    'Delimiter', ',', ...
                                    'HeaderLines', hlines, ...
                                    'CommentStyle', ';' ...
                                    );
                lines_kept = lines_kept + numel(segarray{1});
                hlines = 0;  % We've skipped the header lines, don't skip more lines on the subsequent imports

                idx_start = (step-1)*dataObj.chunksize + 1;
                idx_end = idx_start + length(segarray{:,1}) - 1;

                dataObj.time(idx_start:idx_end)        = segarray{1};
                dataObj.accel_x(idx_start:idx_end)     = segarray{2};
                dataObj.accel_y(idx_start:idx_end)     = segarray{3};
                dataObj.accel_z(idx_start:idx_end)     = segarray{4};
                dataObj.pressure(idx_start:idx_end)    = segarray{5};
                dataObj.temperature(idx_start:idx_end) = segarray{6};

                step = step+1;
            end

            fclose(fID);

            % Check to see if any lines were discarded
            if lines_kept ~= dataObj.ndatapoints
                % TODO: Trim less verbosely
                trimidx = lines_kept + 1;

                dataObj.time(trimidx:end)        = [];
                dataObj.accel_x(trimidx:end)     = [];
                dataObj.accel_y(trimidx:end)     = [];
                dataObj.accel_z(trimidx:end)     = [];
                dataObj.pressure(trimidx:end)    = [];
                dataObj.temperature(trimidx:end) = [];

                dataObj.ndatapoints = lines_kept;
            end
        end


        function readrawdata(dataObj)
            % Read raw data from the XBM
            %
            % Raw data formatting:
            %   Column 1:  Time           (seconds, float)
            %   Column 2:  X acceleration (counts, integer)
            %   Column 3:  Y acceleration (counts, integer)
            %   Column 4:  Z acceleration (counts, integer)
            %   Column 5:  X gyro
            %   Column 6:  Y gyro
            %   Column 7:  Z gyro
            %   Column 8:  W quaternion
            %   Column 9:  X quaternion
            %   Column 10: Y quaternion
            %   Column 11: Z quaternion
            %   Column 12: X magnetometer
            %   Column 13: Y magnetometer
            %   Column 14: Z magnetometer
            %   Column 15: Pressure       (Pascal, integer)        *Sample rate may be different than IMU
            %   Column 16: Temperature    (mill-degree C, integer) *Sample rate may be different than IMU

            fID = fopen(dataObj.filepath);
            hlines = dataObj.nheaderlines;
            formatSpec = '%f %d %d %d %d %d %d %f %f %f %f %d %d %d %d %d';

            step = 1;
            lines_kept = 0;  % Track in case we toss line(s) from the end of the file
            while ~feof(fID)
                segarray = textscan(fID, formatSpec, dataObj.chunksize, ...
                                    'Delimiter', ',', ...
                                    'HeaderLines', hlines, ...
                                    'CommentStyle', ';' ...
                                    );
                lines_kept = lines_kept + numel(segarray{1});
                hlines = 0;  % We've skipped the header lines, don't skip more lines on the subsequent imports

                idx_start = (step-1)*dataObj.chunksize + 1;
                idx_end = idx_start + length(segarray{:,1}) - 1;

                dataObj.time(idx_start:idx_end)        = segarray{1};
                dataObj.accel_x(idx_start:idx_end)     = segarray{2};
                dataObj.accel_y(idx_start:idx_end)     = segarray{3};
                dataObj.accel_z(idx_start:idx_end)     = segarray{4};
                dataObj.gyro_x(idx_start:idx_end)      = segarray{5};
                dataObj.gyro_y(idx_start:idx_end)      = segarray{6};
                dataObj.gyro_z(idx_start:idx_end)      = segarray{7};
                dataObj.quat_w(idx_start:idx_end)      = segarray{8};
                dataObj.quat_x(idx_start:idx_end)      = segarray{9};
                dataObj.quat_y(idx_start:idx_end)      = segarray{10};
                dataObj.quat_z(idx_start:idx_end)      = segarray{11};
                dataObj.mag_x(idx_start:idx_end)       = segarray{12};
                dataObj.mag_y(idx_start:idx_end)       = segarray{13};
                dataObj.mag_z(idx_start:idx_end)       = segarray{14};
                dataObj.pressure(idx_start:idx_end)    = segarray{15};
                dataObj.temperature(idx_start:idx_end) = segarray{16};

                step = step+1;
            end

            fclose(fID);

            % Check to see if any lines were discarded
            if lines_kept ~= dataObj.ndatapoints
                % TODO: Trim less verbosely
                trimidx = lines_kept + 1;

                dataObj.time(trimidx:end)        = [];
                dataObj.accel_x(trimidx:end)     = [];
                dataObj.accel_y(trimidx:end)     = [];
                dataObj.accel_z(trimidx:end)     = [];
                dataObj.gyro_x(trimidx:end)      = [];
                dataObj.gyro_y(trimidx:end)      = [];
                dataObj.gyro_z(trimidx:end)      = [];
                dataObj.quat_w(trimidx:end)      = [];
                dataObj.quat_x(trimidx:end)      = [];
                dataObj.quat_y(trimidx:end)      = [];
                dataObj.quat_z(trimidx:end)      = [];
                dataObj.mag_x(trimidx:end)       = [];
                dataObj.mag_y(trimidx:end)       = [];
                dataObj.mag_z(trimidx:end)       = [];
                dataObj.pressure(trimidx:end)    = [];
                dataObj.temperature(trimidx:end) = [];

                dataObj.ndatapoints = lines_kept;
            end
        end


        function convertdata(dataObj)
            % Convert acceleration data from raw counts to gees
            dataObj.accel_x = dataObj.accel_x/dataObj.countspergee;
            dataObj.accel_y = dataObj.accel_y/dataObj.countspergee;
            dataObj.accel_z = dataObj.accel_z/dataObj.countspergee;

            % Temperature sampled at a lower rate than acceleration, downsample time to match
            tempidx = find(dataObj.temperature ~= 0);
            dataObj.time_temperature = dataObj.time(tempidx);
            dataObj.temperature = dataObj.temperature(tempidx)/1000;  % Convert from mill-degree C to C

            % Pressure sampled at a lower rate than acceleration, downsample time to match
            pressidx = find(dataObj.pressure ~= 0);
            dataObj.time_pressure = dataObj.time(pressidx);
            dataObj.pressure = dataObj.pressure(pressidx);

            % TODO: Convert gyro, quaternion, magnetometer once GCDC provides documentation
        end


        function calcaltitude(dataObj)
            % Find ground level pressure for conversion from pressure to altitude
            dataObj.altitude_meters = 44330*(1 - (dataObj.pressure/dataObj.pressure_groundlevel).^(1/5.255));
            dataObj.altitude_feet = dataObj.altitude_meters * 3.2808;
        end


        function trimdata(dataObj, pressure_idx)
            % TRIMDATA iterates through all timeseries data stored as properties of the xbmini
            % object and trims them according to the input data indices. pressure_idx is a 1x2
            % double specifying start and end indices of the pressure data to retain. All other data
            % is discarded.
            %
            % NOTE: Pressure data may be sampled at a different rate than the temperature and IMU
            % data (IMU likely has a much higher sample rate). Start and end indices of these data
            % are matched as closely as possible to the timestamps corresponding to the input
            % indices.

            % Match pressure indices to corresponding IMU & temperature timestamps
            time_window = dataObj.time_pressure(pressure_idx);
            temperature_idx(1) = find(dataObj.time_temperature >= time_window(1), 1);
            temperature_idx(2) = find(dataObj.time_temperature >= time_window(2), 1);

            time_idx(1) = find(dataObj.time >= time_window(1), 1);
            time_idx(2) = find(dataObj.time >= time_window(2), 1);
            t_start = dataObj.time(time_idx(1));  % For normalization later

            % Trim pressure
            for ii = 1:length(dataObj.pressure_series)
                dataObj.(dataObj.pressure_series{ii}) = dataObj.(dataObj.pressure_series{ii})(pressure_idx(1):pressure_idx(2));
            end

            % Trim temperature
            for ii = 1:length(dataObj.temperature_series)
                dataObj.(dataObj.temperature_series{ii}) = dataObj.(dataObj.temperature_series{ii})(temperature_idx(1):temperature_idx(2));
            end

            % Separate out the IMU properties by dropping temperature & pressure fields from the
            % rest of the public fields. There are a few remaining properties with data that is not
            % time based, a list of these is stored in our private properties, which we use to
            % exclude them from the data trimming.
            allprops = properties(dataObj);
            propstotrim = allprops(~ismember(allprops, dataObj.appendignoreprops));

            % Separate out the IMU properties by dropping temperature & pressure fields
            imu_props = propstotrim(~ismember(propstotrim, [dataObj.pressure_series, dataObj.temperature_series]));
            for ii = 1:length(imu_props)
                dataObj.(imu_props{ii}) = dataObj.(imu_props{ii})(time_idx(1):time_idx(2));
            end

            % Normalize timestamps. Because the timestamps originate from the IMU timeseries upon
            % loading the raw data, normalize based on the IMU timestamp to retain synchronization
            % across the IMU, pressure, and temperature timeseries
            dataObj.time = dataObj.time - t_start;
            dataObj.time_pressure = dataObj.time_pressure - t_start;
            dataObj.time_temperature = dataObj.time_temperature - t_start;
        end
    end

    methods (Static)
        function xbmarray = batch(pathname)
            % Batch process a folder of XBM data files
            %
            % Returns an array of xbmini objects
            flist = AirdropData.subdir(fullfile(pathname, 'DATA-*.csv'));

            nfiles = numel(flist);
            xbmarray = xbmini.empty(nfiles, 1);
            for ii = 1:nfiles
                xbmarray(ii) = xbmini(fullfile(flist(ii).name));
            end
        end
    end
end
