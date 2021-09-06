# XBMINI
`xbmini` is a MATLAB class definition providing the user with a set of methods to parse and analyze raw data files output by GCDC XBmini datalogger

Initialize an `xbmini` object using an absolute filepath to the raw log file:

    myLog = xbmini(filepath);

## Properties
### All logger types
* `filepath`
  * Path to analyzed CSV file
* `analysisdate`
  * Date of analysis, ISO 8601, yyyy-mm-ddTHH:MM:SS+/-HH:MMZ
* `time`
  * Accelerometer time vector, seconds
* `time_temperature`
  * Temperature time vector, seconds
* `time_pressure`
  * Pressure time vector, seconds
* `accel_x`
  * X acceleration, gees
* `accel_y`
  * Y acceleration, gees
* `accel_z`
  * Z acceleration, gees
* `pressure`
  * Raw barometric pressure, pascals
  * Recorded with respect to `time_pressure` time vector
* `temperature`
  * Temperature, Celsius
  * Recorded with respect to `time_temperature` time vector
* `altitude_meters`
  * Pressure altitude, meters, derived from `pressure`
* `altitude_feet`
  * Pressure altitude, feet, derived from `pressure`
* `descentrate`
  * Descent rate, feet per second, derived from pressure altitude (`altitude_feet`) and `time_pressure`

### New XBM Hardware
* `gyro_x`
  * X gyro
* `gyro_y`
  * Y gyro
* `gyro_z`
  * Z gyro
* `quat_w`
  * W quaternion
* `quat_x`
  * X quaternion
* `quat_y`
  * Y quaternion
* `quat_z`
  * Z quaternion
* `mag_x`
  * X magnetometer
* `mag_y`
  * Y magnetometer
* `mag_z`
  * Z magnetometer

NOTE: `time_temperature` and `time_pressure` may be different time vectors than `time` due to potential differences in sampling rate settings and sensor sampling rate capability.

## Methods
### Ordinary Methods
* [`findgroundlevelpressure`](#findgroundlevelpressure) - Interactively identify ground level pressure
* [`finddescentrate`](#finddescentrate) - Interactively identify payload descent rate
* [`append`](#append) - Append another xbmini object to the end of the current object
* [`save`](#save) - Save xbmini instance to MAT file

### Static Methods
* [`getdate`](#getdate) - Generate current local timestamp in ISO 8601 format
* [`countlines`](#countlines) - Count number of lines in file
* [`windowdata`](#windowdata) - Interactively window plotted data

<a name="findgroundlevelpressure"></a>
#### *xbmini*.**findgroundlevelpressure**()
##### Description
Plot the raw pressure data and prompts the user to window the region of the plot where the sensor is at ground level. The average pressure from this windowed region is used to update the object's `pressure_groundlevel` private property. The object's pressure altitudes, `altitude_meters` and `altitude_feet` are recalculated using the updated ground level pressure.

##### Example
    myLog = xbmini(logfilepath);
    myLog.findgroundlevelpressure

<a name="finddescentrate"></a>
#### *xbmini*.**finddescentrate**()
##### Description
Plot the pressure altitude (ft) data and prompts the user to window the region over which to calculate the average descent rate. The average descent rate (ft/s) is calculated over this windowed region and is used to update the object's `descentrate` property.

`descentrate` is also an explicit output of this method

##### Example
    myLog = xbmini(logfilepath);
    descentrate = myLog.finddescentrate;

<a name="append"></a>
#### *xbmini*.**append**()
##### Description
Append a second xbmini object to the end of the current object.

##### Example
    log1 = xbmini(logfilepath1);
    log2 = xbmini(logfilepath2);

    log1.append(log2);

<a name="save"></a>
#### *xbmini*.**save**()
##### Description
Save an instance of the `xbmini` object to a MAT file. File is saved in the same directory as the analyzed log file with the same name as the log.

NOTE: Any existing MAT file of the same name will be overwritten

##### Example
    myLog = xbmini(logfilepath);
    myLog.save

<a name="getdate"></a>
#### *xbmini*.**getdate**()
##### Description
Generate current local timestamp formatted according to [ISO 8601](http://www.iso.org/iso/home/standards/iso8601.htm): `yyyy-mm-ddTHH:MM:SS+/-HH:MMZ`

##### Example
    currentdate = xbmini.getdate()

Returns:

    currentdate =

    2016-07-19T15:11:38-4:00Z

<a name="countlines"></a>
#### *xbmini*.**countlines**(*filepath*)
##### Description
Counts the number of lines present in the specified file, `filepath`, passed as an absolute path. `countlines` attempts to utilize OS specific calls but utilizes MATLAB's built-ins as a fallback.

##### Example
    nlines = xbmini.countlines('.\xbmini.m')

Returns:

    nlines =

        404

<a name="windowdata"></a>
#### *xbmini*.**windowdata**(*ydata*)
##### Description
Plot the input data array, `ydata`, with respect to its data indices along with two vertical lines for the user to window the plotted data.

Execution is blocked by [`uiwait`](http://www.mathworks.com/help/matlab/ref/uiwait.html) and [`msgbox`](http://www.mathworks.com/help/matlab/ref/msgbox.html) to allow the user to zoom/pan the axes and manipulate the window lines as desired. Once the dialog is closed the data indices of the window lines, `dataidx`, and handle to the axes window, `ax`, are returned.

NOTE: Because `ydata` is plotted with respect to its data indices, the indices are floored to the nearest integer in order to mitigate indexing issues.

##### Example
    % Choose a window inside which to shade the area under the curve
    x = 0:10;
    y = x.^2;

    [idx, ax] = xbmini.windowdata(y);

    plot(ax, x, y);
    hold(ax, 'on');
    area(ax, x(idx(1):idx(2)), y(idx(1):idx(2)))
    hold(ax, 'off');
