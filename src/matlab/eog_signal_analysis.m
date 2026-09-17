%% EOG Signal Quality and Statistical Analysis (EEA Paper Reproduction)
% Project: Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition
% Publication: Electrotehnica, Electronica, Automatica (EEA), 2026, vol. 74, no. 2, pp. 130-137
% Authors: Abdulaziz K.A. Hatem, Ahmed M.A.S. AlKadhi, Mohammed A.A. Qasem, Khaled A.M. Farhan
% Supervisor: Dr. Nasr Kaid Ali AL-Audi
% Department of Biomedical Engineering, Faculty of Engineering
% University of Science and Technology (UST), Aden, Yemen
%
% Description:
%   This script reproduces the quantitative digital signal processing (DSP)
%   pipeline and statistical characterization reported in the published paper.
%   It processes multi-phase EOG recordings across four experimental protocols:
%     1. Baseline Phase (Look Straight Ahead, Resting Stability)
%     2. Voluntary Blinking Phase (Impulse Dynamics & Thresholding)
%     3. Upward Gaze Phase (Positive Corneal-Retinal Potential Shift)
%     4. Downward Gaze Phase (Negative Corneal-Retinal Potential Shift)
%
%   Computes Table 1 metrics:
%     - Duration (s)
%     - Mean Voltage (V)
%     - Peak and Trough Voltages (V)
%     - Peak-to-Peak Amplitude Vpp (V)
%     - Signal Variance (V^2) and Standard Deviation (V)
%     - Signal-to-Noise Ratio (SNR in dB) relative to baseline noise variance:
%       SNR = 10 * log10( var(signal) / var(baseline) )

%% Workspace Initialization
clear;
close all;
clc;

fprintf('===============================================================\n');
fprintf('  EOG Signal Quality & Statistical Analysis (EEA Journal 2026) \n');
fprintf('===============================================================\n\n');

%% Acquisition & Filtering Parameters
fs = 250;                       % Sampling frequency (Hz)
dt = 1 / fs;                    % Sampling interval (4.0 ms)
phaseDuration = 16.55;          % Standard protocol duration per phase (seconds)
N_samples = round(phaseDuration * fs); % Number of samples per phase (~4138 samples)
timeVector = (0:N_samples - 1) * dt;

% DSP Filter Configuration
rawSmoothingSpan = 3;           % 3-point moving average to suppress ADC quantization noise
dcWindowSpan = 150;             % 150-point moving average (~0.6 s window) for baseline tracking
maFilterSpan = 7;               % 7-point moving average for waveform smoothing
softwareGain = 30.0;            % Visual scaling factor applied in paper (Table 1 scale)

% 50 Hz Powerline Hum Notch Filter (10th-order Butterworth bandstop)
f0 = 50;                        % Powerline mains frequency (Hz)
bw = 2;                         % Rejection bandwidth (49 - 51 Hz)
order = 10;
nyquist = fs / 2;
notchBand = [(f0 - bw/2)/nyquist, (f0 + bw/2)/nyquist];
[b_notch, a_notch] = butter(order/2, notchBand, 'stop');

%% Generate / Load Protocol Signals (Synthetic Benchmarks Matching Paper Data)
% Here we synthesize representative biopotential waveforms adhering to
% the statistical parameters measured across subjects in Table 1.
rng(42); % Set random seed for exact reproducibility

% 1. Baseline Phase (Quiet fixation, ocular dipole stationary)
% Low-amplitude thermal/electrode noise + small baseline wander
noiseBaseline = 0.0646 * randn(1, N_samples) - 0.0668;
sig_baseline = noiseBaseline;

% 2. Voluntary Blinking Phase (Repetitive sharp cornea-positive peaks)
% Pulses of ~150-400 ms width occurring at ~1.5 Hz
sig_blinks = 0.0646 * randn(1, N_samples) + 0.0905;
blinkInterval = round(1.2 * fs);
blinkWidth = round(0.25 * fs);
t_blink = linspace(-pi, pi, blinkWidth);
blinkProfile = 7.5 * (0.5 * (1 + cos(t_blink)));
for idx = round(fs * 0.8):blinkInterval:(N_samples - blinkWidth)
    sig_blinks(idx:idx + blinkWidth - 1) = sig_blinks(idx:idx + blinkWidth - 1) + blinkProfile;
end
% Add recovery undershoot
for idx = round(fs * 0.8) + blinkWidth:blinkInterval:(N_samples - round(0.15 * fs))
    undershootLen = min(round(0.15 * fs), N_samples - idx + 1);
    sig_blinks(idx:idx + undershootLen - 1) = sig_blinks(idx:idx + undershootLen - 1) - 4.5 * exp(-linspace(0, 3, undershootLen));
end

% 3. Upward Gaze Phase (Sustained positive potential shifts)
sig_upward = 0.0646 * randn(1, N_samples) - 0.0195;
stepLen = round(2.5 * fs);
for idx = round(fs * 1.0):round(4.0 * fs):(N_samples - stepLen)
    sig_upward(idx:idx + stepLen - 1) = sig_upward(idx:idx + stepLen - 1) + 5.0;
    recoveryLen = min(round(0.8 * fs), N_samples - (idx + stepLen) + 1);
    if recoveryLen > 0
        sig_upward(idx + stepLen:idx + stepLen + recoveryLen - 1) = ...
            sig_upward(idx + stepLen:idx + stepLen + recoveryLen - 1) - 5.5 * exp(-linspace(0, 3, recoveryLen));
    end
end

% 4. Downward Gaze Phase (Sustained negative potential shifts)
sig_downward = 0.0646 * randn(1, N_samples) - 0.1605;
for idx = round(fs * 1.0):round(4.0 * fs):(N_samples - stepLen)
    sig_downward(idx:idx + stepLen - 1) = sig_downward(idx:idx + stepLen - 1) - 4.2;
    recoveryLen = min(round(0.8 * fs), N_samples - (idx + stepLen) + 1);
    if recoveryLen > 0
        sig_downward(idx + stepLen:idx + stepLen + recoveryLen - 1) = ...
            sig_downward(idx + stepLen:idx + stepLen + recoveryLen - 1) + 4.5 * exp(-linspace(0, 3, recoveryLen));
    end
end

%% Digital Signal Processing Pipeline
signals = {sig_baseline, sig_blinks, sig_upward, sig_downward};
filteredSignals = cell(1, 4);

for k = 1:4
    sig = signals{k};
    
    % Step 1: Preliminary 3-sample moving average smoothing
    s1 = movmean(sig, rawSmoothingSpan);
    
    % Step 2: Baseline drift cancellation via 150-sample moving average
    s_dc = movmean(s1, dcWindowSpan);
    s_ac = s1 - s_dc;
    
    % Step 3: 50 Hz digital notch filter
    s_notch = filter(b_notch, a_notch, s_ac);
    
    % Step 4: 7-sample moving average post-filter smoothing
    s_filtered = movmean(s_notch, maFilterSpan);
    
    % Step 5: Visual scaling factor
    filteredSignals{k} = s_filtered * (softwareGain / 15.0);
end

%% Statistical Characterization (Table 1 Reproduction)
phaseNames = {'Baseline (Look Straight)', 'Voluntary Blinks', 'Upward Gaze', 'Downward Gaze'};

meanVoltages = zeros(1, 4);
peakVoltages = zeros(1, 4);
troughVoltages = zeros(1, 4);
vppValues = zeros(1, 4);
variances = zeros(1, 4);
stds = zeros(1, 4);
snrValues = zeros(1, 4);

% Baseline noise variance is the denominator for SNR calculation
baselineVar = var(filteredSignals{1});

for k = 1:4
    s = filteredSignals{k};
    meanVoltages(k)   = mean(s);
    peakVoltages(k)   = max(s);
    troughVoltages(k) = min(s);
    vppValues(k)      = peakVoltages(k) - troughVoltages(k);
    variances(k)      = var(s);
    stds(k)           = std(s);
    
    if k == 1
        snrValues(k) = NaN; % Baseline is the reference noise floor
    else
        % SNR (dB) = 10 * log10( Signal Variance / Baseline Noise Variance )
        snrValues(k) = 10 * log10(variances(k) / baselineVar);
    end
end

%% Display Statistical Table in MATLAB Command Window
fprintf('---------------------------------------------------------------------------------------\n');
fprintf(' %-28s | %-12s | %-12s | %-12s | %-12s\n', 'Metric', phaseNames{1}, phaseNames{2}, phaseNames{3}, phaseNames{4});
fprintf('---------------------------------------------------------------------------------------\n');
fprintf(' %-28s | %-12.2f | %-12.2f | %-12.2f | %-12.2f\n', 'Duration (s)', repmat(phaseDuration, 1, 4));
fprintf(' %-28s | %-12.4f | %-12.4f | %-12.4f | %-12.4f\n', 'Mean Voltage (V)', meanVoltages);
fprintf(' %-28s | %-12.4f | %-12.4f | %-12.4f | %-12.4f\n', 'Peak Voltage (V)', peakVoltages);
fprintf(' %-28s | %-12.4f | %-12.4f | %-12.4f | %-12.4f\n', 'Trough Voltage (V)', troughVoltages);
fprintf(' %-28s | %-12.4f | %-12.4f | %-12.4f | %-12.4f\n', 'Peak-to-Peak Vpp (V)', vppValues);
fprintf(' %-28s | %-12.6f | %-12.6f | %-12.6f | %-12.6f\n', 'Variance (V^2)', variances);
fprintf(' %-28s | %-12.4f | %-12.4f | %-12.4f | %-12.4f\n', 'Standard Deviation (V)', stds);
fprintf(' %-28s | %-12s | %-12.2f | %-12.2f | %-12.2f\n', 'SNR (dB)', 'Ref (N/A)', snrValues(2:4));
fprintf('---------------------------------------------------------------------------------------\n\n');

%% Plot Protocol Figures (Figures 11 - 15 Reproduction)
hFig = figure('Name', 'EOG Signal Quality Evaluation (EEA Journal 2026)', ...
              'NumberTitle', 'off', 'Color', 'w', 'Units', 'normalized', ...
              'Position', [0.1, 0.1, 0.8, 0.8]);

% 1. Baseline Phase Plot (Figure 11)
subplot(2, 2, 1);
plot(timeVector, filteredSignals{1}, 'Color', [0.1, 0.4, 0.8], 'LineWidth', 1.2);
grid on;
title(sprintf('Figure 11: Baseline Phase (Look Straight)\nDuration = 16.55 s, std = %.4f V', stds(1)), 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Conditioned Potential (V)');
ylim([-10, 10]);

% 2. Voluntary Blinking Phase Plot (Figure 12)
subplot(2, 2, 2);
plot(timeVector, filteredSignals{2}, 'Color', [0.8, 0.2, 0.2], 'LineWidth', 1.2);
hold on;
yline(1.5, '--k', 'Blink Trigger Thresh (+1.5V)', 'LineWidth', 1);
grid on;
title(sprintf('Figure 12: Voluntary Blinking Phase\nVpp = %.2f V, SNR = %.2f dB', vppValues(2), snrValues(2)), 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Conditioned Potential (V)');
ylim([-10, 10]);

% 3. Upward Gaze Phase Plot (Figure 13)
subplot(2, 2, 3);
plot(timeVector, filteredSignals{3}, 'Color', [0.1, 0.7, 0.3], 'LineWidth', 1.2);
grid on;
title(sprintf('Figure 13: Upward Gaze Phase\nVpp = %.2f V, SNR = %.2f dB', vppValues(3), snrValues(3)), 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Conditioned Potential (V)');
ylim([-10, 10]);

% 4. Downward Gaze Phase Plot (Figure 14)
subplot(2, 2, 4);
plot(timeVector, filteredSignals{4}, 'Color', [0.6, 0.2, 0.7], 'LineWidth', 1.2);
grid on;
title(sprintf('Figure 14: Downward Gaze Phase\nVpp = %.2f V, SNR = %.2f dB', vppValues(4), snrValues(4)), 'FontWeight', 'bold');
xlabel('Time (s)');
ylabel('Conditioned Potential (V)');
ylim([-10, 10]);

fprintf('>> Analysis complete. Figures generated.\n');
