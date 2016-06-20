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
        pressure_sealevel
        temperature
    end
    
    methods
        function dataObj = xbmini(filepath)
            if exist('filepath', 'var')
                dataObj.filepath = filepath;
            else
                [file, pathname] = uigetfile('*.csv', 'Select a XB-mini log file (*.csv)');
                dataObj.filepath = [pathname file];
            end
            dataObj.analysisdate = xbmini.getdate;
        end
    end
    
    methods (Static, Access = private)
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
    end
    
end

