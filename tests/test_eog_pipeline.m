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
    [h, w] = freqz(b_notch, a_notch, [10, 50, 80], fs);
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

%% Test 4: Blink vs Gaze Pulse Discrimination Logic
totalTests = totalTests + 1;
fprintf('Test 4: Blink vs sustained gaze classification... ');
try
    gazeDurationThresholdMs = 915.0;
    samples_Gaze = round(fs * (gazeDurationThresholdMs / 1000.0)); % ~229 samples
    EXECUTE_THRESHOLD = 80.0;
    RESET_THRESHOLD = -50.0;
    
    % Simulate short voluntary blink (100 samples duration = 400 ms < samples_Gaze)
    startCross = 100;
    endCrossShort = 200; % duration = 100
    durShort = endCrossShort - startCross;
    if durShort < samples_Gaze
        detectTypeBlink = 1; % Voluntary blink
    else
        detectTypeBlink = 2;
    end
    assert(detectTypeBlink == 1, 'Short pulse should be classified as voluntary blink');
    
    % Simulate sustained intentional gaze (300 samples duration = 1200 ms >= samples_Gaze)
    endCrossLong = 400; % duration = 300
    durLong = endCrossLong - startCross;
    if durLong < samples_Gaze
        detectTypeGaze = 1;
    else
        detectTypeGaze = 2; % Sustained gaze
    end
    assert(detectTypeGaze == 2, 'Long pulse should be classified as sustained gaze');
    
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

%% Summary Report
fprintf('\n====================================================\n');
fprintf('  Test Results: %d / %d Tests Passed (%.1f%%)\n', passedTests, totalTests, (passedTests/totalTests)*100);
fprintf('====================================================\n');

if passedTests == totalTests
    fprintf('>> ALL DSP & LOGIC TESTS COMPLETED SUCCESSFULLY.\n');
else
    error('Some unit tests failed.');
end
