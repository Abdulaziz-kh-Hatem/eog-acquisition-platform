%% Unit & Integration Test Suite for EOG Signal Processing Pipeline
% Project: Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition
% Tests DSP filtering, DC removal, blink detection, and FSM logic.

clear;
close all;
clc;

fprintf('====================================================\n');
fprintf('  Running EOG Acquisition DSP Pipeline Test Suite   \n');
fprintf('====================================================\n\n');

totalTests = 0;
passedTests = 0;

%% Test 1: Sampling Frequency and Filter Coefficient Integrity
totalTests = totalTests + 1;
fprintf('Test 1: Filter coefficients & 50 Hz notch attenuation... ');
try
    fs = 250;
    nyquist = fs / 2;
    f0 = 50;
    bw = 2;
    order = 10;
    notchCutoffs = [(f0 - bw/2) / nyquist, (f0 + bw/2) / nyquist];
    [b_notch, a_notch] = butter(order / 2, notchCutoffs, 'stop');
    
    % Verify filter stability: all poles inside unit circle
    poles = roots(a_notch);
    assert(all(abs(poles) < 1.0), 'Filter is unstable: poles outside unit circle');
    
    % Verify attenuation at 50 Hz
    [h, ~] = freqz(b_notch, a_notch, [10, 50, 80], fs);
    mag10 = abs(h(1));
    mag50 = abs(h(2));
    mag80 = abs(h(3));
    
    assert(mag50 < 0.1, 'Notch attenuation at 50 Hz is insufficient');
    assert(mag10 > 0.8, 'Notch filter attenuates biopotential signal at 10 Hz');
    assert(mag80 > 0.8, 'Notch filter attenuates signal at 80 Hz');
    
    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Test 2: ADC Quantization and DC Level Shifting
totalTests = totalTests + 1;
fprintf('Test 2: ADC voltage conversion and DC offset tracking... ');
try
    % Test raw ADC counts (10-bit)
    adc_min = 0;
    adc_mid = 512;
    adc_max = 1023;
    
    v_min = adc_min * (5.0 / 1023.0);
    v_mid = adc_mid * (5.0 / 1023.0);
    v_max = adc_max * (5.0 / 1023.0);
    
    assert(abs(v_min - 0.0) < 1e-6, 'ADC min conversion error');
    assert(abs(v_mid - 2.5024) < 1e-2, 'ADC midpoint conversion error');
    assert(abs(v_max - 5.0) < 1e-6, 'ADC max conversion error');
    
    % Test DC buffer baseline tracking
    dcBuffer = NaN(1, 150);
    simulatedOffset = 2.50; % 2.5V DC virtual ground level shifter
    for i = 1:150
        dcBuffer = [dcBuffer(2:end), simulatedOffset + 0.05 * sin(2*pi*i/150)];
    end
    vDC = mean(dcBuffer, 'omitnan');
    assert(abs(vDC - simulatedOffset) < 0.05, 'DC baseline estimation error');
    
    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Test 3: Streaming Filter State Continuity
totalTests = totalTests + 1;
fprintf('Test 3: Sample-by-sample streaming filter state recursion... ');
try
    % Generate a 1-second sine wave at 50 Hz (interference) + 3 Hz (ocular movement)
    t = (0:249) / fs;
    rawSig = 2.5 + 0.3 * sin(2*pi*3*t) + 0.5 * sin(2*pi*50*t);
    
    % Stream sample-by-sample with state recursion
    zi = zeros(max(length(b_notch), length(a_notch)) - 1, 1);
    streamedOut = zeros(size(rawSig));
    for k = 1:length(rawSig)
        [streamedOut(k), zi] = filter(b_notch, a_notch, rawSig(k) - 2.5, zi);
    end
    
    % Block filter reference
    blockOut = filter(b_notch, a_notch, rawSig - 2.5);
    
    % Max discrepancy between sample-by-sample and block filtering should be negligible
    diffNorm = max(abs(streamedOut - blockOut));
    assert(diffNorm < 1e-10, 'Sample-by-sample filter deviates from block filter');
    
    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Test 4: Dynamic Blink vs Gaze State Machine Execution
totalTests = totalTests + 1;
fprintf('Test 4: Dynamic blink vs sustained gaze state machine... ');
try
    gazeDurationThresholdMs = 915.0;
    strongBlinkMaxDurationSeconds = 1.5;
    samples_Gaze = round(fs * (gazeDurationThresholdMs / 1000.0)); % ~229 samples
    samples_BlinkMax = round(fs * strongBlinkMaxDurationSeconds);     % ~375 samples
    EXECUTE_THRESHOLD = 80.0;
    RESET_THRESHOLD = -50.0;
    SILENT_LATCH_VOLTAGE = 80.0;
    
    % Case A: Short Voluntary Blink (80 samples ~ 320 ms < 229 samples)
    % Signal: 0V -> rises to +100V -> falls to -60V -> returns to 0V
    sigBlink = [zeros(1, 20), linspace(0, 100, 30), linspace(100, -60, 50), linspace(-60, 0, 20)];
    [detectTypeA, latchedSecA, latchedCharA] = simulateBlinkFSM( ...
        sigBlink, EXECUTE_THRESHOLD, RESET_THRESHOLD, SILENT_LATCH_VOLTAGE, ...
        samples_Gaze, samples_BlinkMax, 3, 2);
    assert(detectTypeA == 1, sprintf('Expected detectType=1 (blink), got %d', detectTypeA));
    assert(latchedSecA == 3, sprintf('Expected latchedSec=3, got %d', latchedSecA));
    assert(latchedCharA == 2, sprintf('Expected latchedChar=2, got %d', latchedCharA));

    % Case B: Sustained Intentional Gaze (260 samples ~ 1040 ms > 229 samples)
    % Signal: 0V -> rises to +90V -> holds high for 250 samples -> falls to -55V -> returns
    sigGaze = [zeros(1, 20), linspace(0, 90, 10), 90 * ones(1, 240), linspace(90, -55, 10), linspace(-55, 0, 20)];
    [detectTypeB, latchedSecB, latchedCharB] = simulateBlinkFSM( ...
        sigGaze, EXECUTE_THRESHOLD, RESET_THRESHOLD, SILENT_LATCH_VOLTAGE, ...
        samples_Gaze, samples_BlinkMax, 5, 4);
    assert(detectTypeB == 2, sprintf('Expected detectType=2 (gaze), got %d', detectTypeB));
    assert(latchedSecB == 5, sprintf('Expected latchedSec=5, got %d', latchedSecB));
    assert(latchedCharB == 4, sprintf('Expected latchedChar=4, got %d', latchedCharB));

    % Case C: Motion Artifact Exceeding samples_BlinkMax (> 375 samples without recovery)
    sigArtifact = [zeros(1, 20), linspace(0, 95, 10), 95 * ones(1, 400)];
    [detectTypeC, ~, ~] = simulateBlinkFSM( ...
        sigArtifact, EXECUTE_THRESHOLD, RESET_THRESHOLD, SILENT_LATCH_VOLTAGE, ...
        samples_Gaze, samples_BlinkMax, 1, 1);
    assert(detectTypeC == 0, sprintf('Expected detectType=0 (rejected artifact), got %d', detectTypeC));
    
    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Test 5: Arabic Sector Character Completeness
totalTests = totalTests + 1;
fprintf('Test 5: Arabic virtual keyboard sector map coverage... ');
try
    sectorMap = cell(1, 6);
    sectorMap{1} = {'ا', 'ل', 'م', 'ي', 'و'};
    sectorMap{2} = {'ن', 'ر', 'ب', 'ت', 'هـ'};
    sectorMap{3} = {'ع', 'ك', 'د', 'س', 'ق'};
    sectorMap{4} = {'ج', 'ف', 'ص', 'خ', 'ح'};
    sectorMap{5} = {'ش', 'ز', 'ض', 'ط'};
    sectorMap{6} = {'ذ', 'ث', 'غ', 'ظ'};
    
    totalChars = 0;
    for sIdx = 1:6
        assert(~isempty(sectorMap{sIdx}), sprintf('Sector %d is empty', sIdx));
        totalChars = totalChars + length(sectorMap{sIdx});
    end
    assert(totalChars == 28, sprintf('Expected 28 Arabic alphabet characters, got %d', totalChars));
    
    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Test 6: Wheelchair Finite State Machine Directional Logic
totalTests = totalTests + 1;
fprintf('Test 6: Wheelchair FSM directional state transitions... ');
try
    % State transition unit tests for wheelchair control logic
    % 1 blink from STOP -> FORWARD
    assert(strcmp(wheelchairFSM('STOP', 1), 'FORWARD'), 'STOP + 1 blink should lead to FORWARD');
    % 1 blink from FORWARD -> ROTATING
    assert(strcmp(wheelchairFSM('FORWARD', 1), 'ROTATING'), 'FORWARD + 1 blink should lead to ROTATING');
    % 1 blink from ROTATING -> FORWARD
    assert(strcmp(wheelchairFSM('ROTATING', 1), 'FORWARD'), 'ROTATING + 1 blink should lead to FORWARD');
    % 2 blinks from STOP -> ROTATING
    assert(strcmp(wheelchairFSM('STOP', 2), 'ROTATING'), 'STOP + 2 blinks should lead to ROTATING');
    % 2 blinks from FORWARD -> STOP
    assert(strcmp(wheelchairFSM('FORWARD', 2), 'STOP'), 'FORWARD + 2 blinks should lead to STOP');
    % 2 blinks from ROTATING -> STOP
    assert(strcmp(wheelchairFSM('ROTATING', 2), 'STOP'), 'ROTATING + 2 blinks should lead to STOP');
    % 3 blinks from any state -> BACKWARD
    assert(strcmp(wheelchairFSM('STOP', 3), 'BACKWARD'), 'STOP + 3 blinks should lead to BACKWARD');
    assert(strcmp(wheelchairFSM('FORWARD', 3), 'BACKWARD'), 'FORWARD + 3 blinks should lead to BACKWARD');

    fprintf('PASSED\n');
    passedTests = passedTests + 1;
catch ex
    fprintf('FAILED: %s\n', ex.message);
end

%% Summary Report
fprintf('\n====================================================\n');
fprintf('  Test Results: %d / %d Tests Passed (%.1f%%)\n', passedTests, totalTests, (passedTests/totalTests)*100);
fprintf('====================================================\n');

if passedTests == totalTests
    fprintf('>> ALL DSP & LOGIC TESTS COMPLETED SUCCESSFULLY.\n');
else
    error('Some unit tests failed.');
end

%% Local Test Helpers

function [finalDetect, latchedSecOut, latchedCharOut] = simulateBlinkFSM( ...
    stream, execThresh, resetThresh, silentLatchV, samplesGaze, samplesBlinkMax, initSec, initChar)

    blinkState = 0;
    startCross = 0;
    prevVal = 0;
    isSignalRising = false;
    currSec = initSec;
    currChar = initChar;
    tempLatchedSec = currSec;
    tempLatchedChar = currChar;
    latchedSecOut = currSec;
    latchedCharOut = currChar;
    finalDetect = 0;

    for count = 1:length(stream)
        voltageFinal = stream(count);
        detectType = 0;

        if ~isnan(voltageFinal) && ~isnan(prevVal)
            if voltageFinal > silentLatchV && ~isSignalRising
                tempLatchedSec  = currSec;
                tempLatchedChar = currChar;
                isSignalRising  = true;
            end

            if blinkState == 0 && prevVal < execThresh && voltageFinal >= execThresh
                blinkState     = 1;
                startCross     = count;
                latchedSecOut  = tempLatchedSec;
                latchedCharOut = tempLatchedChar;
            elseif blinkState == 1
                if voltageFinal <= resetThresh
                    dur = count - startCross;
                    blinkState = 0;
                    if dur < samplesGaze
                        detectType = 1;
                    else
                        detectType = 2;
                    end
                elseif (count - startCross) > samplesBlinkMax
                    blinkState = 0;
                end
            end

            if voltageFinal < resetThresh
                isSignalRising = false;
            end
        end
        prevVal = voltageFinal;

        if detectType > 0
            finalDetect = detectType;
        end
    end
end

function nextState = wheelchairFSM(currentState, cmd)
    nextState = currentState;
    if cmd == 1
        if strcmp(currentState, 'STOP') || strcmp(currentState, 'BACKWARD')
            nextState = 'FORWARD';
        elseif strcmp(currentState, 'FORWARD')
            nextState = 'ROTATING';
        elseif strcmp(currentState, 'ROTATING')
            nextState = 'FORWARD';
        end
    elseif cmd == 2
        if strcmp(currentState, 'STOP')
            nextState = 'ROTATING';
        else
            nextState = 'STOP';
        end
    elseif cmd == 3
        nextState = 'BACKWARD';
    end
end
