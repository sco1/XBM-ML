classdef xbmini < handle
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
        analysisdate      % Date of analysis, ISO 8601, yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
        time              % Accelerometer time vector, seconds
        time_temperature  % Temperature time vector, seconds
        time_pressure     % Pressure time vector, seconds
        accel_x           % X acceleration, gees
        accel_y           % Y acceleration, gees
        accel_z           % Z acceleration, gees
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
            % TODO: Check for empty/invalid path
            dataObj.analysisdate = xbmini.getdate;
            dataObj.nlines = xbmini.countlines(dataObj.filepath);
            initializedata(dataObj);
            readrawdata(dataObj);
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
            [idx, ax] = xbmini.windowdata(dataObj.pressure);
            
            % Calculate and plot average pressure in the windowed region
            dataObj.pressure_groundlevel = mean(dataObj.pressure(idx(1):idx(2)));
            line(idx, ones(2, 1)*dataObj.pressure_groundlevel, 'Color', 'r', 'Parent', ax);
            
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
            [idx, ax] = xbmini.windowdata(dataObj.altitude_feet);
            
            % Because we just plotted altitude vs. data index, update the
            % plot to altitude vs. time but save the limits and use them so
            % the plot doesn't get zoomed out
            oldxlim = floor(ax.XLim);
            
            % Catch indexing issues if plot isn't zoomed "properly"
            oldxlim(oldxlim < 1) = 1; 
            oldxlim(oldxlim > length(dataObj.altitude_feet)) = length(dataObj.altitude_feet);
            
            oldylim = ax.YLim;
            plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);
            xlim(ax, dataObj.time_pressure(oldxlim));
            ylim(ax, oldylim);
            
            % Calculate and plot linear fit
            myfit = polyfit(dataObj.time_pressure(idx(1):idx(2)), dataObj.altitude_feet(idx(1):idx(2)), 1);
            altitude_feet_fit = dataObj.time_pressure(idx(1):idx(2)).*myfit(1) + myfit(2);
            hold(ax, 'on');
            plot(dataObj.time_pressure(idx(1):idx(2)), altitude_feet_fit, 'r', 'Parent', ax)
            hold(ax, 'off');
            xlabel('Time (s)');
            ylabel('Altitude (ft. AGL)');
            
            % Set outputs
            descentrate = myfit(1);
            dataObj.descentrate = descentrate;
        end
      
        
        function save(dataObj)
            % SAVE saves an instance of the xbmini object to a MAT file. 
            % File is saved in the same directory as the analyzed log file 
            % with the same name as the log.
            %
            % Any existing MAT file of the same name will be overwritten
            [pathname, filename] = fileparts(dataObj.filepath);
            save(fullfile(pathname, [filename '.mat']), 'dataObj');
        end
    end
    
    methods (Access = private)
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
        end
        
        
        function readrawdata(dataObj)
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
        end
        
        
        function calcaltitude(dataObj)
            % Find ground level pressure for conversion from pressure to
            % altitude
            dataObj.altitude_meters = 44330*(1 - (dataObj.pressure/dataObj.pressure_groundlevel).^(1/5.255));
            dataObj.altitude_feet = dataObj.altitude_meters * 3.2808;
        end
    end
    
    
    methods (Static)
        function date = getdate()
            % Generate current local timestamp and format according to
            % ISO 8601: yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
            if ~verLessThan('MATLAB', '8.4')  % datetime added in R2014b
                timenow = datetime('now', 'TimeZone', 'local');
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%sZ', char(tzoffset(timenow)));
            else
                UTCoffset = -java.util.Date().getTimezoneOffset/60;  % See what Java thinks your TZ offset is
                timenow = clock;
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%i:00Z', UTCoffset);
            end
            
            date = datestr(timenow, formatstr);
        end
        
        
        function nlines = countlines(filepath)
            % COUNTLINES counts the number of lines present in the 
            % specified file, filepath, passed as an absolute path.
            % COUNTLINES attempts to utilize OS specific calls but utilizes
            % MATLAB's built-ins as a fallback.
            
            % Attempt to use system specific calls, otherwise use MATLAB
            if ispc
                syscall = sprintf('find /v /c "" "%s"', filepath);  % Count lines in file
                [~, cmdout] = system(syscall);
                % cmdout is of form: ---------- filepath: nlines
                % We can parse this with a regex that searches for 1 or
                % more digits anchored by a colon + whitespace
                tmp = regexp(cmdout, '(?<=(:\s))(\d*)', 'match');
                nlines = str2double(tmp{1});
            elseif ismac || isunix
                syscall = sprintf('wc -l < "%s"', filepath);
                [~, cmdout] = system(syscall);
                % wc -l returns number of lines directly
                nlines = str2double(cmdout);
            else
                % Can't determine OS, use MATLAB instead
                fID = fopen(filepath, 'rt');
                
                blocksize = 16384;  % Size of block to read in, bytes
                nlines = 0;
                while ~feof(fID)
                    % Read in CSV file as binary file in chunks, count the
                    % number of line feed characters (ASCII 10)
                    nlines = nlines + sum(fread(fID, blocksize, 'char') == char(10));
                end
                
                fclose(fID);
            end
        end
        
        function [dataidx, ax] = windowdata(ydata)
            % WINDOWDATA plots the input data array, ydata, with respect to
            % its data indices along with two vertical lines for the user 
            % to window the plotted data. 
            % 
            % Execution is blocked by UIWAIT and MSGBOX to allow the user 
            % to zoom/pan the axes and manipulate the window lines as 
            % desired. Once the dialog is closed the data indices of the 
            % window lines, dataidx, and handle to the axes are returned.
            %
            % Because ydata is plotted with respect to its data indices,
            % the indices are floored to the nearest integer in order to
            % mitigate indexing issues.
            h.fig = figure('WindowButtonUpFcn', @xbmini.stopdrag); % Set the mouse button up Callback on figure creation
            h.ax = axes('Parent', h.fig);
            plot(ydata, 'Parent', h.ax);
            
            % Create our window lines, set the default line X locations at
            % 25% and 75% of the axes limits
            currxlim = xlim;
            axeswidth = currxlim(2) - currxlim(1);
            h.line_1 = line(ones(1, 2)*axeswidth*0.25, ylim(h.ax), ...
                            'Color', 'g', ...
                            'ButtonDownFcn', {@xbmini.startdrag, h} ...
                            );
            h.line_2 = line(ones(1, 2)*axeswidth*0.75, ylim(h.ax), ...
                            'Color', 'g', ...
                            'ButtonDownFcn', {@xbmini.startdrag, h} ...
                            );
            
            % Add appropriate listeners to the X and Y axes to ensure
            % window lines are visible and the appropriate height
            xlisten = addlistener(h.ax, 'XLim', 'PostSet', @(hObj,eventdata) xbmini.checklinesx(hObj, eventdata, h));
            ylisten = addlistener(h.ax, 'YLim', 'PostSet', @(hObj,eventdata) xbmini.changelinesy(hObj, eventdata, h));
            
            % Use uiwait to allow the user to manipulate the axes and
            % window lines as desired
            uiwait(msgbox('Window Region of Interest Then Press OK'))
            
            % Set outputs
            dataidx = floor(sort([h.line_1.XData(1), h.line_2.XData(1)]));
            ax = h.ax;
            
            % Clean up
            delete([xlisten, ylisten]);
        end
    end
    
    
    methods (Static, Access = private)
        function startdrag(lineObj, ~, h)
            % Helper function for data windowing, sets figure
            % WindowButtonMotionFcn callback to dragline helper
            % while line is being clicked on & dragged
            h.fig.WindowButtonMotionFcn = {@xbmini.dragline, h, lineObj};
        end
        
        
        function stopdrag(hObj, ~)
            % Helper function for data windowing, clears figure window
            % WindowButtonMotionFcn callback when mouse button is released
            % after dragging the line
            hObj.WindowButtonMotionFcn = '';
        end
        
        
        function checklinesx(~, ~, h)
            % Helper function for data windowing, checks the X indices of
            % the vertical lines to make sure they're still within the X
            % axis limits of the data axes object
            currxlim = h.ax.XLim;
            currlinex_1 = h.line_1.XData(1);
            currlinex_2 = h.line_2.XData(1);
            
            % Set X coordinate of any line outside the axes limits to the
            % axes limit
            if currlinex_1 < currxlim(1)
                h.line_1.XData = [1, 1]*currxlim(1);
            end
            
            if currlinex_1 > currxlim(2)
                h.line_1.XData = [1, 1]*currxlim(2);
            end
            
            if currlinex_2 < currxlim(1)
                h.line_2.XData = [1, 1]*currxlim(1);
            end
            
            if currlinex_2 > currxlim(2)
                h.line_2.XData = [1, 1]*currxlim(2);
            end
            
        end
        
        
        function changelinesy(~, ~, h)
            % Helper function for data windowing, sets the height of both
            % vertical lines to the height of the axes object
            h.line_1.YData = ylim(h.ax);
            h.line_2.YData = ylim(h.ax);
        end

        
        function dragline(~, ~, h, lineObj)
            % Helper function for data windowing, updates the x coordinate
            % of the dragged line to the current location of the mouse
            % button
            currentX = h.ax.CurrentPoint(1, 1);
            
            % Prevent dragging outside of the current axes limits
            if currentX < h.ax.XLim(1)
                lineObj.XData = [1, 1]*h.ax.XLim(1);
            elseif currentX > h.ax.XLim(2)
                lineObj.XData = [1, 1]*h.ax.XLim(2);
            else
                lineObj.XData = [1, 1]*currentX;
            end
        end
    end
end