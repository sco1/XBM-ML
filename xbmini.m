classdef xbmini < handle
    %XBMINI Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        filepath
        analysisdate
        time
        time_temperature
        time_pressure
        accel_x
        accel_y
        accel_z
        pressure
        temperature
        altitude_meters
        altitude_feet
        descentrate
    end
    
    properties (Access = private)
        nlines
        nheaderlines = 8;  % number of header lines
        ndatapoints
        chunksize = 5000;  % Data chunk size for reading in raw data
        pressure_sealevel = 101325;  % Default sea level, Pascals
        countspergee = 2048;  % Raw data counts per gee, for accelerometer
    end
    
    methods
        function dataObj = xbmini(filepath)
            if exist('filepath', 'var')
                filepath = fullfile(filepath);  % Ensure correct file separators
                dataObj.filepath = filepath;
            else
                [file, pathname] = uigetfile('*.csv', 'Select a XB-mini log file (*.csv)');
                dataObj.filepath = [pathname file];
            end
            dataObj.analysisdate = xbmini.getdate;
            dataObj.nlines = xbmini.countlines(dataObj.filepath);
            initializedata(dataObj);
            readrawdata(dataObj);
            convertdata(dataObj);
            calcaltitude(dataObj);
        end
        
        
        function findsealevelpressure(dataObj)
            [idx, ax] = xbmini.windowdata(dataObj.pressure);
            dataObj.pressure_sealevel = mean(dataObj.pressure(idx(1):idx(2)));
            line(idx, ones(2, 1)*dataObj.pressure_sealevel, 'Color', 'r', 'Parent', ax);
            calcaltitude(dataObj);  % Recalculate altitudes
        end
        
        
        function descentrate = finddescentrate(dataObj)
            [idx, ax] = xbmini.windowdata(dataObj.altitude_feet);
            myfit = polyfit(dataObj.time_pressure(idx(1):idx(2)), dataObj.altitude_feet(idx(1):idx(2)), 1);  % Calculate linear fit
            altitude_feet_fit = dataObj.time_pressure(idx(1):idx(2)).*myfit(1) + myfit(2);  % Calculate altitude from linear fit
            
            % Because we just plotted altitude vs. data index, update the
            % plot to altitude vs. time but save the limits and use them so
            % the plot doesn't get zoomed out
            oldxlim = floor(ax.XLim);
            if oldxlim < 1  % Catch indexing issue if plot isn't zoomed "properly"
                oldxlim = 1;
            end
            oldylim = ax.YLim;
            plot(dataObj.time_pressure, dataObj.altitude_feet, 'Parent', ax);
            xlim(ax, dataObj.time_pressure(oldxlim));
            ylim(ax, oldylim);
            hold(ax, 'on');
            plot(dataObj.time_pressure(idx(1):idx(2)), altitude_feet_fit, 'r', 'Parent', ax)
            hold(ax, 'off');
            
            % Set outputs
            descentrate = myfit(1);
            dataObj.descentrate = descentrate;
        end
      
        
        function save(dataObj)
            [pathname, filename] = fileparts(dataObj.filepath);
            save(fullfile(pathname, [filename '.mat']), 'dataObj');
        end
    end
    
    methods (Access = private)
        function initializedata(dataObj)
            dataObj.ndatapoints = dataObj.nlines - dataObj.nheaderlines;
            dataObj.time = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_x = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_y = zeros(dataObj.ndatapoints, 1);
            dataObj.accel_z = zeros(dataObj.ndatapoints, 1);
            dataObj.pressure = zeros(dataObj.ndatapoints, 1);
            dataObj.temperature = zeros(dataObj.ndatapoints, 1);
        end
        
        
        function readrawdata(dataObj)
            fID = fopen(dataObj.filepath);
            hlines = dataObj.nheaderlines;
            formatSpec = '%f %d %d %d %d %d';
            
            step = 1;
            while ~feof(fID)
                if step > ceil(dataObj.nlines/dataObj.chunksize)
                    % Detect infinite loop and break out of loop
                    % Should be fixed by the CommentStyle property of the textscan call
                    break
                end
                
                segarray = textscan(fID, formatSpec, dataObj.chunksize, ...
                    'Delimiter', ',', ...
                    'HeaderLines', hlines, ...
                    'CommentStyle', ';' ...  % Data file ends with a commented string that puts default textscan into an infinite loop
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
            dataObj.altitude_meters = 44330*(1 - (dataObj.pressure/dataObj.pressure_sealevel).^(1/5.255));  % Altitude, meters
            dataObj.altitude_feet = dataObj.altitude_meters * 3.2808;
        end
    end
    
    
    methods (Static)
        function date = getdate()
            if ~verLessThan('MATLAB', '8.4')  % datetime added in R2014b
                timenow = datetime('now', 'TimeZone', 'local');
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%sZ', char(tzoffset(timenow)));
            else
                UTCoffset = -java.util.Date().getTimezoneOffset/60;  % See what Java thinks your TZ offset is
                timenow = clock;
                formatstr = sprintf('yyyy-mm-ddTHH:MM:SS%i:00Z', UTCoffset);
            end
            
            date = datestr(timenow, formatstr);  % ISO 8601 format
        end
        
        
        function nlines = countlines(filepath)
            % Count the number of lines present in the specified file.
            % filepath should be an absolute path
            
            filepath = fullfile(filepath);  % Make sure we're using the correct OS file separators
            
            % Attempt to use system specific calls, otherwise use MATLAB
            if ispc
                syscall = sprintf('find /v /c "" "%s"', filepath);
                [~, cmdout] = system(syscall);
                tmp = regexp(cmdout, '(?<=(:\s))(\d*)', 'match');
                nlines = str2double(tmp{1});
            elseif ismac || isunix
                syscall = sprintf('wc -l < "%s"', filepath);
                [~, cmdout] = system(syscall);
                nlines = str2double(cmdout);
            else
                % Can't determine OS, use MATLAB instead
                fID = fopen(filepath, 'rt');
                
                nlines = 0;
                while ~feof(fID)
                    nlines = nlines + sum(fread(fID, 16384, 'char') == char(10));
                end
                
                fclose(fID);
            end
        end
        
        function [dataidx, ax] = windowdata(ydata)
            h.fig = figure('WindowButtonUpFcn', @xbmini.stopdrag);
            h.ax = axes('Parent', h.fig);
            
            plot(ydata, 'Parent', h.ax);
            h.line_1 = line([2 2], ylim(h.ax), ...
                            'Color', 'g', ...
                            'ButtonDownFcn', {@xbmini.startdrag, h} ...
                            );
            h.line_2 = line([5 5], ylim(h.ax), ...
                            'Color', 'g', ...
                            'ButtonDownFcn', {@xbmini.startdrag, h} ...
                            );
                        
            xlisten = addlistener(h.ax, 'XLim', 'PostSet', @(hObj,eventdata) xbmini.checklinesx(hObj, eventdata, h));
            ylisten = addlistener(h.ax, 'YLim', 'PostSet', @(hObj,eventdata) xbmini.changelinesy(hObj, eventdata, h));
            
            uiwait(msgbox('Window Region of Interest Then Press OK'))
            delete([xlisten, ylisten]);
            dataidx = floor(sort([h.line_1.XData(1), h.line_2.XData(1)]));
            ax = h.ax;
        end
    end
    
    
    methods (Static, Access = private)
        function startdrag(lineObj, ~, h)
            h.fig.WindowButtonMotionFcn = {@xbmini.dragline, h, lineObj};
        end
        
        
        function stopdrag(hObj, ~)
            hObj.WindowButtonMotionFcn = '';
        end
        
        
        function checklinesx(~, ~, h)
            currxlim = h.ax.XLim;
            currlinex_1 = h.line_1.XData(1);
            currlinex_2 = h.line_2.XData(1);
            
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
            h.line_1.YData = ylim(h.ax);
            h.line_2.YData = ylim(h.ax);
        end

        
        function dragline(~, ~, h, lineObj)
            currentX = h.ax.CurrentPoint(1, 1);
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