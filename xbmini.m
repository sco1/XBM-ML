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
end

