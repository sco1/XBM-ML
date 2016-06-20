classdef xbmini
    %UNTITLED2 Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        filepath
        analysisdate
        time
        accel_x
        accel_y
        accel_z
        pressure
        temperature
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
    end
end