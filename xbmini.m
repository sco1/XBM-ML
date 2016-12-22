classdef xbmini < handle & AirdropData
    % XBMINI is a MATLAB class definition providing the user with a set of
    % methods to parse and analyze raw data files output by GCDC XBmini
    % datalogger
    %
    % Initialize an xbmini object using an absolute filepath to the raw
    % log file:
    %     myLog = xbmini(filepath);
    % 
    % xbmini methods:
    %     findgroundlevelpressure - Interactively identify ground level pressure
    %     finddescentrate         - Interactively identify payload descent rate
    %     save                    - Save xbmini instance to MAT file
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
    end
    
    properties (Access = private)
        nlines                          % Number of lines in CSV file
        nheaderlines = 8;               % Number of header lines in CSV file
        ndatapoints                     % Number of data lines in CSV file
        chunksize = 5000;               % Data chunk size for reading in raw data
        countspergee = 2048;            % Raw data counts per gee, for converting accelerometer data
        pressure_groundlevel = 101325;  % Ground level pressure, pascals, default is 101325 Pa
        islegacy                        % Boolean to differentiate between new/old XBmini
    end
    
    methods
        function dataObj = xbmini(filepath)
            % Check to see if a filepath has been passed to xbmini, prompt
            % user to select a file if one hasn't been passed
            if exist('filepath', 'var')
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
            initializedata(dataObj);
            
            % Pick appropriate data parser based on logger type
            getLoggerType(dataObj);
            if dataObj.islegacy
                readrawdata_legacy(dataObj);
            else
                readrawdata(dataObj);
            end
            
            convertdata(dataObj);
            calcaltitude(dataObj);
        end
        
        
        function findgroundlevelpressure(dataObj)
            % FINDGROUNDLEVELPRESSURE Plots the raw pressure data and 
            % prompts the user to window the region of the plot where the 
            % sensor is at ground level. The average pressure from this 
            % windowed region is used to update the object's pressure_groundlevel 
            % private property. The object's pressure altitude is also 
            % recalculated using the updated ground level pressure.
            h.fig = figure;
            h.ax = axes;
            h.ls = plot(h.ax, dataObj.pressure);
            idx = xbmini.windowdata(h.ls);
            
            % Calculate and plot average pressure in the windowed region
            dataObj.pressure_groundlevel = mean(dataObj.pressure(idx(1):idx(2)));
            line(idx, ones(2, 1)*dataObj.pressure_groundlevel, 'Color', 'r', 'Parent', h.ax);
            
            % Recalculate altitudes
            calcaltitude(dataObj);
        end
        
        
        function descentrate = finddescentrate(dataObj)
            % FINDDESCENTRATE Plots the pressure altitude (ft) data and 
            % prompts the user to window the region over which to calculate
            % the descent rate. The average descent rate (ft/s) is 
            % calculated over this windowed region and is used to update
            % the object's descentrate property. 
            % descentrate is also an explicit output of this method
            h.fig = figure;
            h.ax = axes;
            h.ls = plot(h.ax, dataObj.altitude_feet);
            idx = xbmini.windowdata(h.ls);
            
            % Because we just plotted altitude vs. data index, update the
            % plot to altitude vs. time but save the limits and use them so
            % the plot doesn't get zoomed out
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
            altitude_feet_fit = dataObj.time_pressure(idx(1):idx(2)).*myfit(1) + myfit(2);
            hold(h.ax, 'on');
            plot(dataObj.time_pressure(idx(1):idx(2)), altitude_feet_fit, 'r', 'Parent', h.ax)
            hold(h.ax, 'off');
            xlabel('Time (s)');
            ylabel('Altitude (ft. AGL)');
            
            % Set outputs
            descentrate = myfit(1);
            dataObj.descentrate = descentrate;
        end
      
        
        function save(dataObj, varargin)
            % SAVE saves an instance of the xbmini object to a MAT file. 
            % File is saved in the same directory as the analyzed log file 
            % with the same name as the log.
            %
            % Any existing MAT file of the same name will be overwritten
            [pathname, filename] = fileparts(dataObj.filepath);
            savefilepath = fullfile(pathname, [filename '.mat']);
            
            p = inputParser;
            p.FunctionName = 'xbmini:save';
            p.addParameter('savefilepath', savefilepath, @ischar);
            p.addParameter('noclass', false, @islogical);
            p.addParameter('verboseoutput', false, @islogical);
            p.parse(varargin{:});
            
            if p.Results.noclass
                % Save property values only, not class instance
                propstosave = properties(dataObj);  % Get list of public properties
                
                for ii = 1:length(propstosave)
                    prop = propstosave{ii};
                    tmp.(prop) = dataObj.(prop);
                end

                save(p.Results.savefilepath, '-struct', 'tmp');
            else
                save(p.Results.savefilepath, 'dataObj');
            end
                       
            if p.Results.verboseoutput
                if p.results.noclass
                    fprintf('%s object public properties saved to ''%s''\n', class(dataObj), p.Results.savefilepath);
                else
                    fprintf('%s object instance saved to ''%s''\n', class(dataObj), p.Results.savefilepath);
                end
            end
        end
    end
    
    methods (Hidden, Access = protected)
        function getLoggerType(dataObj)
            % Pull logger type from the first line of the data file header
            fID = fopen(dataObj.filepath, 'r');
            tline = fgetl(fID);  % Get first line of data
            fclose(fID);
            
            tmp = regexp(tline, '(X16\S*)(?=\,)', 'Match');
            dataObj.loggertype = tmp{1};  % De-nest cell
            switch dataObj.loggertype
                case 'X16-B1100-mini'
                    dataObj.islegacy = true;
                case 'X16-ham'
                    dataObj.islegacy = false;
                otherwise
                    msgID = 'xbmini:getLoggerType:UnsupportedDevice';
                    error(msgID, ...
                          'Unsupported data logger ''%s'' detected', dataObj.loggertype);
            end
        end
        
        
        function initializedata(dataObj)
            % Preallocate data arrays based on number of lines in the data
            % file
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
            % Header lines formatting:
            % Line 1: Header: Misc.
            % Line 2: Header: Misc.
            % Line 3: Header: Start time/date
            % Line 4: Header: Temperature, battery voltage
            % Line 5: Header: Sample rate
            % Line 6: Header: Deadband
            % Line 7: Header: Deadband timeout
            % Line 8: Header: Column labels
            % 
            % Raw data formatting:
            % Column 1: Time           (seconds, float)
            % Column 2: X acceleration (counts, integer)
            % Column 3: Y acceleration (counts, integer)
            % Column 4: Z acceleration (counts, integer)
            % Column 5: Pressure       (Pascal, integer)        *Sample rate may be different than accel
            % Column 6: Temperature    (mill-degree C, integer) *Sample rate may be different than accel
            
            fID = fopen(dataObj.filepath);
            hlines = dataObj.nheaderlines;
            formatSpec = '%f %d %d %d %d %d';
            
            step = 1;
            while ~feof(fID)
                if step > ceil(dataObj.nlines/dataObj.chunksize)
                    % Data file may end with a commented string that puts
                    % textscan into an infinite loop when run with the
                    % default parameters. Detect this infinite loop and
                    % break out if it occurs.
                    % This issue should be fixed by the 'CommentStyle'
                    % argument to textscan, but this is left just in case
                    break
                end
                
                segarray = textscan(fID, formatSpec, dataObj.chunksize, ...
                                    'Delimiter', ',', ...
                                    'HeaderLines', hlines, ...
                                    'CommentStyle', ';' ...
                                    );
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
        end
        
        
        function readrawdata(dataObj)
            % Read raw data from the XBM
            %
            % Header lines formatting:
            % Line 1: Header: Misc.
            % Line 2: Header: Misc.
            % Line 3: Header: Start time/date
            % Line 4: Header: Temperature, battery voltage
            % Line 5: Header: Sample rate
            % Line 6: Header: Deadband
            % Line 7: Header: Deadband timeout
            % Line 8: Header: Column labels
            % 
            % Raw data formatting:
            % Column 1:  Time           (seconds, float)
            % Column 2:  X acceleration (counts, integer)
            % Column 3:  Y acceleration (counts, integer)
            % Column 4:  Z acceleration (counts, integer)
            % Column 5:  X gyro
            % Column 6:  Y gyro
            % Column 7:  Z gyro
            % Column 8:  W quaternion
            % Column 9:  X quaternion
            % Column 10: Y quaternion
            % Column 11: Z quaternion
            % Column 12: X magnetometer
            % Column 13: Y magnetometer
            % Column 14: Z magnetometer
            % Column 15: Pressure       (Pascal, integer)        *Sample rate may be different than IMU
            % Column 16: Temperature    (mill-degree C, integer) *Sample rate may be different than IMU
            
            fID = fopen(dataObj.filepath);
            hlines = dataObj.nheaderlines;
            formatSpec = '%f %d %d %d %d %d %d %f %f %f %f %d %d %d %d %d';
            
            step = 1;
            while ~feof(fID)
                if step > ceil(dataObj.nlines/dataObj.chunksize)
                    % Data file may end with a commented string that puts
                    % textscan into an infinite loop when run with the
                    % default parameters. Detect this infinite loop and
                    % break out if it occurs.
                    % This issue should be fixed by the 'CommentStyle'
                    % argument to textscan, but this is left just in case
                    break
                end
                
                segarray = textscan(fID, formatSpec, dataObj.chunksize, ...
                                    'Delimiter', ',', ...
                                    'HeaderLines', hlines, ...
                                    'CommentStyle', ';' ...
                                    );
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
                dataObj.mag_x(idx_start:idx_end)         = segarray{12};
                dataObj.mag_y(idx_start:idx_end)         = segarray{13};
                dataObj.mag_z(idx_start:idx_end)         = segarray{14};
                dataObj.pressure(idx_start:idx_end)    = segarray{15};
                dataObj.temperature(idx_start:idx_end) = segarray{16};
                
                step = step+1;
            end
            
            fclose(fID);
        end
        
        
        function convertdata(dataObj)
            % Convert acceleration data from raw counts to gees
            dataObj.accel_x = dataObj.accel_x/dataObj.countspergee;
            dataObj.accel_y = dataObj.accel_y/dataObj.countspergee;
            dataObj.accel_z = dataObj.accel_z/dataObj.countspergee;
            
            % Temperature sampled at a lower rate than acceleration,
            % downsample time to match
            tempidx = find(dataObj.temperature ~= 0);
            dataObj.time_temperature = dataObj.time(tempidx);
            dataObj.temperature = dataObj.temperature(tempidx)/1000;  % Convert from mill-degree C to C
            
            % Pressure sampled at a lower rate than acceleration,
            % downsample time to match
            pressidx = find(dataObj.pressure ~= 0);
            dataObj.time_pressure = dataObj.time(pressidx);
            dataObj.pressure = dataObj.pressure(pressidx);
            
            % TODO: Convert gyro, quaternion, M-thing (wtf is this) once
            % GCDC provides documentation
        end
        
        
        function calcaltitude(dataObj)
            % Find ground level pressure for conversion from pressure to
            % altitude
            dataObj.altitude_meters = 44330*(1 - (dataObj.pressure/dataObj.pressure_groundlevel).^(1/5.255));
            dataObj.altitude_feet = dataObj.altitude_meters * 3.2808;
        end
    end
    
    methods (Static)
        function xbmarray = batchxbmini(pathname)
            % Batch process a folder of XBM data files
            % Returns an array of xbmini objects
            flist = AirdropData.subdir(fullfile(pathname, 'DATA-*.csv'));
            
            for ii = 1:length(flist)
                xbmarray(ii) = xbmini(fullfile(flist(ii).name));
            end
        end
    end
end
