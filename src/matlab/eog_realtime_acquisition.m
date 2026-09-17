%% Real-Time EOG Signal Acquisition and Human-Machine Interface
% Project: Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition
% Author: Abdulaziz K.A. Hatem, Ahmed M.A.S. AlKadhi, Mohammed A.A. Qasem, Khaled A.M. Farhan
% Supervisor: Dr. Nasr Kaid Ali AL-Audi
% Department of Biomedical Engineering, Faculty of Engineering
% University of Science and Technology (UST), Aden, Yemen
%
% Description:
%   Real-time serial acquisition from Arduino Uno (ATmega328P ADC) at 250 Hz.
%   Applies digital signal processing to extract voluntary eye movements:
%     1. Raw ADC conversion to voltage (0 - 5 V range, 4.88 mV / LSB).
%     2. 3-point moving average to attenuate high-frequency ADC quantization noise.
%     3. 150-point moving average baseline subtraction to remove DC electrode offset.
%     4. 10th-order 50 Hz digital Butterworth notch filter (bandwidth 2 Hz)
%        to suppress powerline mains interference.
%     5. 7-point moving average post-filter smoothing for clean peak discrimination.
%     6. Two-stage software amplification (25x * 12x = 300x total software gain).
%   Finite State Machine (FSM) decodes voluntary blink sequences and sustained
%   gaze durations to operate dual assistive modalities:
%     - Wheelchair Navigation: Forward, Stop, Backward, and Differential Rotation.
%     - Arabic Virtual Speller: 6-sector polar scanning keyboard with Arabic characters.

%% Workspace Initialization
clear;
close all;
clc;

fprintf('=== EOG Acquisition & Assistive Interface Initializing ===\n');

%% Hardware & Serial Communication Parameters
arduinoPort = 'COM7';               % Serial COM port assigned to Arduino Uno
baudRate = 115200;                  % High baud rate for low-latency 250 Hz streaming
bluetoothDeviceAddress = "002411010D19"; % MAC address of HC-05 module on wheelchair

% Wheelchair Bluetooth connection (graceful fallback if hardware is offline)
b_dev = [];
bt_ok = false;
fprintf('Attempting connection to wheelchair Bluetooth module (%s)...\n', bluetoothDeviceAddress);
try
    b_dev = bluetooth(bluetoothDeviceAddress, 1);
    bt_ok = true;
    fprintf('>> Wheelchair Bluetooth connection established successfully.\n');
catch
    % Fallback: allow signal acquisition and speller to run without wheelchair
    fprintf(2, '>> Notice: Bluetooth connection failed or device not paired.\n');
    fprintf(2, '   Continuing in standalone acquisition mode.\n');
end

%% Assistive Interface Timing & Calibration Constants
% Polar keyboard automatic scanning timing
SCAN_SPEED_SECTORS = 1.2;          % Dwell time per main sector (seconds)
SCAN_SPEED_CHARS = 1.2;            % Dwell time per character within selected sector (seconds)
TIME_FIRST_CHAR_WAIT = 1.0;        % Initial pause before starting sub-sector scan (seconds)

% Graphic layout settings
CHAR_SPACING = 0.33;
FONT_SIZE_NORMAL = 45;
FONT_SIZE_ACTIVE = 60;

% Biopotential detection thresholds (software-scaled units, 300x software gain)
% 80.0 V display threshold corresponds to ~267 mV at ADC input, ~100 uV at skin
SILENT_LATCH_VOLTAGE = 80.0;       % Pre-trigger voltage to lock currently highlighted target
EXECUTE_THRESHOLD = 80.0;          % Positive blink onset threshold (V)
RESET_THRESHOLD = -50.0;           % Negative recovery threshold for blink completion (V)

% Temporal window thresholds
gazeDurationThresholdMs = 915.0;         % Threshold separating voluntary blinks from sustained gaze
strongBlinkMaxDurationSeconds = 1.5;     % Maximum plausible blink width (rejects motion artifacts)
blinkSequenceTimeoutSeconds = 1.0;       % Window for multi-blink command integration (seconds)
reentryPauseSeconds = 0.8;               % Guard time after command execution (seconds)
postSelectionDelaySeconds = 2.0;         % Post-selection stabilization delay (seconds)

%% Arabic Virtual Keyboard Character Layout
% 6 polar sectors dividing the 28 Arabic letters grouped by visual/frequency layout
sectorMap = cell(1, 6);
sectorMap{1} = {'ا', 'ل', 'م', 'ي', 'و'};
sectorMap{2} = {'ن', 'ر', 'ب', 'ت', 'هـ'};
sectorMap{3} = {'ع', 'ك', 'د', 'س', 'ق'};
sectorMap{4} = {'ج', 'ف', 'ص', 'خ', 'ح'};
sectorMap{5} = {'ش', 'ز', 'ض', 'ط'};
sectorMap{6} = {'ذ', 'ث', 'غ', 'ظ'};

%% Serial Port Configuration & Buffer Flush
s = [];
try
    fprintf('Connecting to Arduino Uno on %s at %d bps...\n', arduinoPort, baudRate);
    
    % Clear any residual serial port instances on the target port
    existingPorts = serialportfind('Port', arduinoPort);
    if ~isempty(existingPorts)
        delete(existingPorts);
        pause(1.5);
    end
    
    s = serialport(arduinoPort, baudRate);
    configureTerminator(s, "LF");
    fprintf('>> Serial port opened successfully.\n');
catch ex
    fprintf(2, 'Serial Connection Error: %s\n', ex.message);
    fprintf(2, 'Check that Arduino is connected and COM port is correct.\n');
    return;
end

% Flush serial buffer to ensure clean synchronization
fprintf('Flushing input buffer...\n');
flush(s);

measuredFs = 250; % Target sampling frequency (250 samples/second)
fprintf('>> Acquisition sampling rate: %d Hz (T = 4.0 ms)\n', measuredFs);

%% Digital Filter Design (50 Hz IIR Notch & Moving Average)
% Software amplification factors
targetTotalAmplification = 300.0;
amplificationFactor = 25.0;
secondaryAmplificationFactor = targetTotalAmplification / amplificationFactor; % 12.0

% 50 Hz powerline interference notch filter (10th-order Butterworth bandstop)
f0 = 50;                     % Powerline hum fundamental frequency (50 Hz in Yemen)
bw = 2;                      % Notch rejection bandwidth (49 Hz to 51 Hz)
order = 10;                  % Filter order
nyquist = measuredFs / 2;    % Nyquist frequency (125 Hz)
notchCutoffs = [(f0 - bw/2) / nyquist, (f0 + bw/2) / nyquist];
[b_notch, a_notch] = butter(order / 2, notchCutoffs, 'stop');

% Scope display buffer parameters (8-second rolling window)
scrollWidth = 2000;          % 2000 samples @ 250 Hz = 8.0 seconds
timeVector = (0:scrollWidth - 1) / measuredFs;

% Convert temporal thresholds from seconds to discrete sample counts
samples_Gaze      = round(measuredFs * (gazeDurationThresholdMs / 1000.0)); % ~229 samples
samples_BlinkMax  = round(measuredFs * strongBlinkMaxDurationSeconds);     % ~375 samples
samples_Timeout   = round(measuredFs * blinkSequenceTimeoutSeconds);       % ~250 samples
samples_Reentry   = round(measuredFs * reentryPauseSeconds);               % ~200 samples
samples_FirstWait = round(measuredFs * TIME_FIRST_CHAR_WAIT);              % ~250 samples
samples_ScanSec   = round(measuredFs * SCAN_SPEED_SECTORS);                % ~300 samples
samples_ScanChar  = round(measuredFs * SCAN_SPEED_CHARS);                  % ~300 samples

%% Graphical User Interface Construction
C_BG   = [0.00, 0.00, 0.00];  % Black background for contrast
C_NEON = [0.00, 0.85, 1.00];  % Neon cyan highlight color
C_DIM  = [0.15, 0.15, 0.15];  % Dark gray inactive sector background

hFig = figure('Name', 'EOG Signal Acquisition & Assistive Control Interface', ...
              'NumberTitle', 'off', ...
              'Color', C_BG, ...
              'Units', 'normalized', ...
              'Position', [0, 0, 1, 1], ...
              'MenuBar', 'none');

% --- Real-Time EOG Oscilloscope Display ---
axSig = axes('Parent', hFig, ...
             'Units', 'normalized', ...
             'Position', [0.05, 0.80, 0.85, 0.15], ...
             'Color', [0.05, 0.05, 0.05], ...
             'XColor', 'w', ...
             'YColor', 'w', ...
             'XLim', [0, timeVector(end)], ...
             'YLim', [-100, 100]);
hold(axSig, 'on');
grid(axSig, 'on');
xlabel(axSig, 'Time (s)', 'Color', 'w');
ylabel(axSig, 'Scaled Potential (V)', 'Color', 'w');
title(axSig, 'Real-Time Conditioned EOG Waveform (fs = 250 Hz)', 'Color', C_NEON);

hLine = plot(axSig, timeVector, NaN(1, scrollWidth), 'Color', C_NEON, 'LineWidth', 2);
yline(axSig, EXECUTE_THRESHOLD, '-.r', 'LineWidth', 1.5, 'Label', 'Blink Threshold (+80V)', 'LabelColor', 'r');
yline(axSig, RESET_THRESHOLD, '-.c', 'LineWidth', 1.5, 'Label', 'Reset Baseline (-50V)', 'LabelColor', 'c');

% --- Wheelchair Status Subpanel ---
pnlWheel = uipanel('Parent', hFig, ...
                   'Units', 'normalized', ...
                   'Position', [0.10, 0.10, 0.80, 0.60], ...
                   'BackgroundColor', C_BG, ...
                   'BorderType', 'none', ...
                   'Visible', 'on');

uicontrol('Parent', pnlWheel, ...
          'Style', 'text', ...
          'String', 'WHEELCHAIR CONTROL MODE', ...
          'Units', 'normalized', ...
          'Position', [0.10, 0.50, 0.80, 0.20], ...
          'BackgroundColor', C_BG, ...
          'ForegroundColor', C_NEON, ...
          'FontSize', 44, ...
          'FontWeight', 'bold');

txtWheelSt = uicontrol('Parent', pnlWheel, ...
                       'Style', 'text', ...
                       'String', 'STANDBY', ...
                       'Units', 'normalized', ...
                       'Position', [0.10, 0.30, 0.80, 0.15], ...
                       'BackgroundColor', C_BG, ...
                       'ForegroundColor', 'w', ...
                       'FontSize', 26);

% --- Virtual Keyboard Subpanel ---
pnlSpell = uipanel('Parent', hFig, ...
                   'Units', 'normalized', ...
                   'Position', [0.05, 0.02, 0.90, 0.75], ...
                   'BackgroundColor', C_BG, ...
                   'BorderType', 'none', ...
                   'Visible', 'off');

txtOut = uicontrol('Parent', pnlSpell, ...
                   'Style', 'edit', ...
                   'Units', 'normalized', ...
                   'Position', [0.10, 0.90, 0.80, 0.08], ...
                   'BackgroundColor', [0.10, 0.10, 0.15], ...
                   'ForegroundColor', 'w', ...
                   'FontSize', 28, ...
                   'String', '', ...
                   'Enable', 'inactive', ...
                   'FontWeight', 'bold');

axCirc = axes('Parent', pnlSpell, ...
              'Units', 'normalized', ...
              'Position', [0.00, 0.00, 1.00, 0.88], ...
              'Color', C_BG, ...
              'XColor', 'none', ...
              'YColor', 'none', ...
              'XLim', [-1.1, 1.1], ...
              'YLim', [-1.1, 1.1]);
axis(axCirc, 'equal');
hold(axCirc, 'on');

% Outer Polar Wedges (6 Sectors)
NUM_SECTORS = 6;
wedges = gobjects(1, NUM_SECTORS);
lbls   = gobjects(1, NUM_SECTORS);
angles = linspace(90, -270, NUM_SECTORS + 1);

for i = 1:NUM_SECTORS
    th = linspace(deg2rad(angles(i)), deg2rad(angles(i + 1)), 50);
    wedges(i) = patch(axCirc, [0, cos(th), 0], [0, sin(th), 0], C_DIM, ...
                      'EdgeColor', [0.3, 0.3, 0.3], 'LineWidth', 2);
    midAngle = (deg2rad(angles(i)) + deg2rad(angles(i + 1))) / 2;
    lbls(i)  = text(axCirc, 0.65 * cos(midAngle), 0.65 * sin(midAngle), ...
                    strjoin(sectorMap{i}, ' '), ...
                    'Color', 'w', 'FontSize', 18, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

% Inner Polar Wedges (Character Level Breakdown)
MAX_INNER_ITEMS = 6;
innerWedges = gobjects(1, MAX_INNER_ITEMS);
innerLbls   = gobjects(1, MAX_INNER_ITEMS);
subCharObjs = gobjects(1, MAX_INNER_ITEMS);

for k = 1:MAX_INNER_ITEMS
    innerWedges(k) = patch(axCirc, NaN, NaN, [0.10, 0.10, 0.25], ...
                           'EdgeColor', [0.4, 0.4, 0.6], 'LineWidth', 2, 'Visible', 'off');
    innerLbls(k)   = text(axCirc, 0, 0, '', 'Color', 'w', 'FontSize', 20, ...
                          'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'Visible', 'off');
    subCharObjs(k) = text(axCirc, 0, 0, '', 'Visible', 'off');
end

txtSpSt = text(axCirc, 0, -1.05, 'READY', 'Color', C_NEON, 'FontSize', 16, 'HorizontalAlignment', 'center');

%% Signal Processing Buffers & Finite State Machine Initialization
voltageDataToPlot = NaN(1, scrollWidth);
rawBufferSmooth   = NaN(1, 3);    % 3-sample moving average buffer
dcBuffer          = NaN(1, 150);  % 150-sample moving average DC estimation buffer
maFilterBuffer    = NaN(1, 7);    % 7-sample moving average post-filter buffer

% Initial state vector for 50 Hz notch filter streaming recursion
zi_main = zeros(max(length(b_notch), length(a_notch)) - 1, 1);

% State variables
mode            = 'WHEEL';        % Operating mode: 'WHEEL' or 'SPELL'
wheelState      = 'STOP';         % Navigation state: 'STOP', 'FORWARD', 'BACKWARD', 'ROTATING'
spellState      = 'SECTOR';       % Speller state: 'SECTOR' (group) or 'CHAR' (letter)
currSec         = 1;              % Active keyboard sector index (1 to 6)
currChar        = 1;              % Active character subsector index
sectorHistory   = [];             % Navigation history for backspace backtracking
latchedSec      = 1;              % Confirmed sector index
latchedChar     = 1;              % Confirmed character index
tempLatchedSec  = 1;              % Candidate sector latched on initial signal rise
tempLatchedChar = 1;              % Candidate character latched on initial signal rise
isSignalRising  = false;          % Flag to latch selection only once per blink onset

% Event timing and classification counters
count        = 0;
timerScan    = 0;
timerPause   = 0;
blinkState   = 0;                 % 0 = resting, 1 = pulse above execution threshold
startCross   = 0;                 % Sample index where signal crossed threshold
blinkCount   = 0;                 % Count of sequential blinks detected
lastBlinkEnd = 0;                 % Sample index of most recent completed blink
prevVal      = 0;                 % Previous sample potential for zero-crossing check

% Initialize visual state to sector 1
updateSectorVisuals(wedges, lbls, 1, C_NEON, C_DIM);
flush(s);

%% Real-Time Acquisition, DSP Filtering & Control Loop
fprintf('>> Starting acquisition loop. Close GUI figure window to stop.\n');

while ishandle(hFig)
    % Read available serial samples from Arduino
    if s.NumBytesAvailable > 0
        try
            lineStr = readline(s);
            valRaw = str2double(lineStr);
            if isnan(valRaw)
                continue;
            end
            count = count + 1;

            % 1. Convert 10-bit ADC integer count (0 - 1023) to analog voltage (0 - 5 V)
            voltageRaw = valRaw * (5.0 / 1023.0);

            % 2. First-stage 3-sample moving average smoothing
            rawBufferSmooth = [rawBufferSmooth(2:end), voltageRaw];
            vToProc = mean(rawBufferSmooth, 'omitnan');

            % 3. Estimate DC baseline drift via 150-sample moving average (0.6 s window)
            dcBuffer = [dcBuffer(2:end), vToProc];
            vDC = mean(dcBuffer, 'omitnan');

            voltageFinal = NaN;
            if ~isnan(vDC)
                % 4. Subtract DC baseline to center ocular biopotential around 0 V
                vAC = vToProc - vDC;

                % 5. 50 Hz digital notch filter to remove powerline mains interference
                [vAC, zi_main] = filter(b_notch, a_notch, vAC, zi_main);

                % 6. Primary amplification
                vAmp = vAC * amplificationFactor;

                % 7. Second-stage 7-sample moving average smoothing
                maFilterBuffer = [maFilterBuffer(2:end), vAmp];
                vMA = mean(maFilterBuffer, 'omitnan');

                % 8. Secondary amplification to reach target visual threshold scale
                voltageFinal = vMA * secondaryAmplificationFactor;
            end

            % Update rolling oscilloscope buffer and refresh display every 5 samples
            if ~isnan(voltageFinal)
                voltageDataToPlot = [voltageDataToPlot(2:end), voltageFinal];
                if mod(count, 5) == 0
                    set(hLine, 'YData', voltageDataToPlot);
                end
            end

            % Event discrimination: classify pulse as blink vs sustained gaze
            detectType = 0; % 0: None, 1: Voluntary Blink, 2: Sustained Gaze
            if ~isnan(voltageFinal) && ~isnan(prevVal)
                % Silent latch: capture current target as soon as signal starts rising
                if voltageFinal > SILENT_LATCH_VOLTAGE && ~isSignalRising
                    tempLatchedSec  = currSec;
                    tempLatchedChar = currChar;
                    isSignalRising  = true;
                end

                % Onset crossing: signal transitions above positive execution threshold
                if blinkState == 0 && prevVal < EXECUTE_THRESHOLD && voltageFinal >= EXECUTE_THRESHOLD
                    blinkState  = 1;
                    startCross  = count;
                    latchedSec  = tempLatchedSec;
                    latchedChar = tempLatchedChar;
                elseif blinkState == 1
                    % Offset crossing: signal returns below negative recovery threshold
                    if voltageFinal <= RESET_THRESHOLD
                        dur = count - startCross;
                        blinkState = 0;
                        if dur < samples_Gaze
                            detectType = 1; % Short pulse -> voluntary blink
                        else
                            detectType = 2; % Extended duration -> deliberate gaze
                        end
                    elseif (count - startCross) > samples_BlinkMax
                        % Exceeded maximum plausible blink duration: reject as motion artifact
                        blinkState = 0;
                    end
                end

                % Reset rising edge latch once potential fully returns to baseline
                if voltageFinal < RESET_THRESHOLD
                    isSignalRising = false;
                end
            end
            prevVal = voltageFinal;

            % Virtual speller automatic circular scanning
            if count > timerPause
                if strcmp(mode, 'SPELL')
                    if strcmp(spellState, 'SECTOR')
                        limit = samples_ScanSec;
                    else
                        limit = samples_ScanChar;
                    end

                    if (count - timerScan) > limit
                        if strcmp(spellState, 'SECTOR')
                            currSec = mod(currSec, NUM_SECTORS) + 1;
                            updateSectorVisuals(wedges, lbls, currSec, C_NEON, C_DIM);
                        else
                            chars = sectorMap{currSec};
                            totalItems = length(chars) + 1; % Characters + 'حذف'
                            currChar = mod(currChar, totalItems) + 1;
                            highlightInnerSector(innerWedges, innerLbls, currChar, C_NEON, totalItems);
                        end
                        timerScan = count;
                    end
                end

                % Handle detected events
                if detectType == 1
                    % Increment sequential blink count within timeout window
                    if (count - lastBlinkEnd) > samples_Timeout
                        blinkCount = 1;
                    else
                        blinkCount = blinkCount + 1;
                    end
                    lastBlinkEnd = count;
                    strSt = sprintf('BLINKS: %d', blinkCount);
                    if strcmp(mode, 'WHEEL')
                        set(txtWheelSt, 'String', strSt);
                    else
                        set(txtSpSt, 'String', strSt);
                    end

                elseif detectType == 2
                    % Sustained gaze: execute cancel / backspace
                    blinkCount = 0;
                    if strcmp(mode, 'SPELL')
                        if strcmp(spellState, 'CHAR')
                            % Exit character view back to outer sector level
                            spellState = 'SECTOR';
                            hideInnerSectors(innerWedges, innerLbls);
                            hideSubChars(subCharObjs, lbls, currSec);
                            updateSectorVisuals(wedges, lbls, currSec, C_NEON, C_DIM);
                            timerPause = count + samples_Reentry;
                            timerScan  = timerPause;
                        else
                            % Backspace: delete last typed letter
                            txt = char(get(txtOut, 'String'));
                            if ~isempty(txt)
                                set(txtOut, 'String', txt(1:end-1));
                            end
                            set(txtSpSt, 'String', 'BACKSPACE');
                            if ~isempty(sectorHistory)
                                sectorHistory(end) = [];
                            end
                        end
                    end
                end

                % Evaluate multi-blink commands upon timeout expiration
                if (blinkCount > 0) && ((count - lastBlinkEnd) > samples_Timeout)
                    cmd = blinkCount;
                    blinkCount = 0;

                    if cmd >= 4
                        % Safety toggle: 4+ blinks toggles between Wheelchair and Speller modes
                        set(txtOut, 'String', '');
                        sectorHistory = [];
                        if strcmp(mode, 'WHEEL')
                            % Transition to Speller Mode (halt wheelchair motion first)
                            wheelState = 'STOP';
                            sendWheelchairCommand(b_dev, bt_ok, '2');

                            mode = 'SPELL';
                            set(pnlWheel, 'Visible', 'off');
                            set(pnlSpell, 'Visible', 'on');
                            spellState = 'SECTOR';
                            currSec = 1;
                            updateSectorVisuals(wedges, lbls, 1, C_NEON, C_DIM);
                        else
                            % Transition to Wheelchair Mode
                            mode = 'WHEEL';
                            set(pnlSpell, 'Visible', 'off');
                            set(pnlWheel, 'Visible', 'on');
                            hideInnerSectors(innerWedges, innerLbls);
                            hideSubChars(subCharObjs, lbls, currSec);
                        end

                    elseif strcmp(mode, 'WHEEL')
                        % Wheelchair finite state machine
                        if cmd == 1
                            if strcmp(wheelState, 'STOP') || strcmp(wheelState, 'BACKWARD')
                                wheelState = 'FORWARD';
                                sendWheelchairCommand(b_dev, bt_ok, '1');
                                set(txtWheelSt, 'String', 'FORWARD');
                            elseif strcmp(wheelState, 'FORWARD')
                                wheelState = 'ROTATING';
                                sendWheelchairCommand(b_dev, bt_ok, '4');
                                set(txtWheelSt, 'String', 'ROTATING');
                            elseif strcmp(wheelState, 'ROTATING')
                                wheelState = 'FORWARD';
                                sendWheelchairCommand(b_dev, bt_ok, '1');
                                set(txtWheelSt, 'String', 'FORWARD');
                            end

                        elseif cmd == 2
                            if strcmp(wheelState, 'STOP')
                                wheelState = 'ROTATING';
                                sendWheelchairCommand(b_dev, bt_ok, '4');
                                set(txtWheelSt, 'String', 'ROTATING');
                            else
                                wheelState = 'STOP';
                                sendWheelchairCommand(b_dev, bt_ok, '2');
                                set(txtWheelSt, 'String', 'STOP');
                            end

                        elseif cmd == 3
                            wheelState = 'BACKWARD';
                            sendWheelchairCommand(b_dev, bt_ok, '3');
                            set(txtWheelSt, 'String', 'BACKWARD');
                        end

                    elseif strcmp(mode, 'SPELL')
                        % Arabic virtual speller finite state machine
                        if cmd == 1
                            if strcmp(spellState, 'SECTOR')
                                % Drill down into selected sector
                                targetSec = latchedSec;
                                sectorHistory = [sectorHistory, targetSec];
                                spellState = 'CHAR';
                                currChar   = 1;
                                currSec    = targetSec;
                                activateInsideView(subCharObjs, wedges, lbls, innerWedges, innerLbls, ...
                                                   currSec, sectorMap, C_BG, C_NEON, ...
                                                   CHAR_SPACING, FONT_SIZE_NORMAL, FONT_SIZE_ACTIVE);
                                timerScan = count + samples_FirstWait;
                            else
                                % Select active character or delete option
                                targetIdx = latchedChar;
                                chars = sectorMap{currSec};
                                if targetIdx > length(chars)
                                    % Selected 'حذف' (Delete)
                                    txt = char(get(txtOut, 'String'));
                                    if ~isempty(txt)
                                        set(txtOut, 'String', txt(1:end-1));
                                    end
                                    set(txtSpSt, 'String', 'BACKSPACE');
                                    timerPause = count + samples_Reentry;
                                    timerScan  = timerPause;
                                else
                                    % Append selected letter
                                    charToWrite = chars{targetIdx};
                                    txt = get(txtOut, 'String');
                                    set(txtOut, 'String', [txt, charToWrite]);
                                    spellState = 'SECTOR';
                                    hideInnerSectors(innerWedges, innerLbls);
                                    hideSubChars(subCharObjs, lbls, currSec);
                                    updateSectorVisuals(wedges, lbls, currSec, C_NEON, C_DIM);
                                    latchedSec = 0;
                                    set(txtSpSt, 'String', ['SELECTED: ', charToWrite]);
                                    timerPause = count + samples_Reentry;
                                    timerScan  = timerPause + round(measuredFs * 0.5);
                                end
                            end

                        elseif cmd == 2
                            if strcmp(spellState, 'SECTOR')
                                % Backspace and re-enter last visited sector
                                txt = char(get(txtOut, 'String'));
                                if ~isempty(txt)
                                    set(txtOut, 'String', txt(1:end-1));
                                    if ~isempty(sectorHistory)
                                        lastGroup = sectorHistory(end);
                                        sectorHistory(end) = [];
                                        sectorHistory = [sectorHistory, lastGroup];
                                        currSec = lastGroup;
                                        spellState = 'CHAR';
                                        currChar = 1;
                                        activateInsideView(subCharObjs, wedges, lbls, innerWedges, innerLbls, ...
                                                           currSec, sectorMap, C_BG, C_NEON, ...
                                                           CHAR_SPACING, FONT_SIZE_NORMAL, FONT_SIZE_ACTIVE);
                                        timerScan = count + samples_FirstWait;
                                        set(txtSpSt, 'String', 'CORRECTION');
                                    end
                                end
                            else
                                % Append space character
                                txt = get(txtOut, 'String');
                                set(txtOut, 'String', [txt, ' ']);
                            end

                        elseif cmd == 3
                            if strcmp(spellState, 'CHAR')
                                % Exit character level without selecting
                                spellState = 'SECTOR';
                                hideInnerSectors(innerWedges, innerLbls);
                                hideSubChars(subCharObjs, lbls, currSec);
                                updateSectorVisuals(wedges, lbls, currSec, C_NEON, C_DIM);
                                set(txtSpSt, 'String', 'EXIT GROUP');
                                timerPause = count + samples_Reentry;
                                timerScan  = timerPause;
                            else
                                % Clear entire typed sentence
                                set(txtOut, 'String', '');
                                sectorHistory = [];
                                set(txtSpSt, 'String', 'CLEAR ALL');
                            end
                        end
                    end
                end
            end
            drawnow limitrate;
        catch
            continue;
        end
    end
end

%% Resource Cleanup
if ~isempty(s)
    clear s;
end
if bt_ok && ~isempty(b_dev)
    clear b_dev;
end
fprintf('>> Acquisition terminated and ports closed cleanly.\n');

%% Local Helper Functions

function updateSectorVisuals(w, l, idx, cOn, cOff)
    % Update outer sector highlights during keyboard scanning
    set(w, 'FaceColor', cOff, 'EdgeColor', [0.3, 0.3, 0.3]);
    set(l, 'Visible', 'on', 'Color', 'w', 'FontSize', 18);
    set(w(idx), 'FaceColor', cOn, 'EdgeColor', 'w');
    set(l(idx), 'Color', 'k', 'FontSize', 22);
end

function activateInsideView(~, w, l, innerW, innerL, secIdx, map, cBg, cOn, ~, ~, ~)
    % Reveal inner character wedges for the selected sector
    set(w, 'FaceColor', cBg, 'EdgeColor', 'none');
    set(l, 'Visible', 'off');
    chars = map{secIdx};
    n = length(chars);
    totalItems = n + 1; % Characters + 'حذف'
    
    baseColors = [0.10, 0.15, 0.35;
                  0.10, 0.25, 0.20;
                  0.30, 0.12, 0.30;
                  0.28, 0.18, 0.08;
                  0.08, 0.20, 0.35;
                  0.35, 0.10, 0.10];
              
    angleStep = 360 / totalItems;
    startAngle = 90;
    
    for k = 1:totalItems
        a1 = deg2rad(startAngle - (k - 1) * angleStep);
        a2 = deg2rad(startAngle - k * angleStep);
        theta = linspace(a1, a2, 60);
        
        if k <= n
            faceC = baseColors(mod(k - 1, size(baseColors, 1)) + 1, :);
            labelStr = chars{k};
            lblColor = [0.85, 0.85, 0.85];
            lblSize  = 22;
        else
            faceC = [0.35, 0.05, 0.05];
            labelStr = 'حذف';
            lblColor = [1.00, 0.45, 0.45];
            lblSize  = 20;
        end
        
        set(innerW(k), 'XData', [0, cos(theta), 0], 'YData', [0, sin(theta), 0], ...
                       'FaceColor', faceC, 'EdgeColor', [0.5, 0.5, 0.7], ...
                       'LineWidth', 2.5, 'Visible', 'on', 'FaceAlpha', 0.9);
        
        midAngle = (a1 + a2) / 2;
        textR = 0.62;
        set(innerL(k), 'Position', [textR * cos(midAngle), textR * sin(midAngle), 0], ...
                       'String', labelStr, 'Color', lblColor, 'FontSize', lblSize, ...
                       'FontWeight', 'bold', 'Visible', 'on');
    end
    
    for k = (totalItems + 1):length(innerW)
        set(innerW(k), 'Visible', 'off');
        set(innerL(k), 'Visible', 'off');
    end
    
    % Highlight first character sub-sector
    set(innerW(1), 'FaceColor', cOn, 'EdgeColor', 'w', 'LineWidth', 3);
    set(innerL(1), 'Color', [0, 0, 0], 'FontSize', 26);
end

function highlightInnerSector(innerW, innerL, activeIdx, cOn, maxItems)
    % Update highlighting among character sub-sectors during inner scan
    baseColors = [0.10, 0.15, 0.35;
                  0.10, 0.25, 0.20;
                  0.30, 0.12, 0.30;
                  0.28, 0.18, 0.08;
                  0.08, 0.20, 0.35;
                  0.35, 0.10, 0.10];
              
    for k = 1:maxItems
        if ~strcmp(get(innerW(k), 'Visible'), 'on')
            continue;
        end
        if k == activeIdx
            set(innerW(k), 'FaceColor', cOn, 'EdgeColor', 'w', 'LineWidth', 3);
            set(innerL(k), 'Color', [0, 0, 0], 'FontSize', 26);
        else
            if k == maxItems
                set(innerW(k), 'FaceColor', [0.35, 0.05, 0.05], 'EdgeColor', [0.5, 0.5, 0.7], 'LineWidth', 2.5);
                set(innerL(k), 'Color', [1.00, 0.45, 0.45], 'FontSize', 20);
            else
                faceC = baseColors(mod(k - 1, size(baseColors, 1)) + 1, :);
                set(innerW(k), 'FaceColor', faceC, 'EdgeColor', [0.5, 0.5, 0.7], 'LineWidth', 2.5);
                set(innerL(k), 'Color', [0.85, 0.85, 0.85], 'FontSize', 22);
            end
        end
    end
end

function hideInnerSectors(innerW, innerL)
    % Hide inner character sectors when returning to main sector scan
    set(innerW, 'Visible', 'off');
    set(innerL, 'Visible', 'off');
end

function hideSubChars(subObjs, l, secIdx)
    % Restore sector labels when closing inner character view
    set(subObjs, 'Visible', 'off');
    set(l(secIdx), 'Visible', 'on');
end

function sendWheelchairCommand(b_dev, bt_ok, cmdChar)
    % Send motion command over Bluetooth to wheelchair Arduino
    if bt_ok && ~isempty(b_dev)
        try
            write(b_dev, cmdChar, "char");
        catch
            try
                fprintf(b_dev, '%s', cmdChar);
            catch
            end
        end
    end
end
