# Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition

[![Published](https://img.shields.io/badge/Published-EEA%20Journal%202026-green.svg)](https://doi.org/10.46904/eea.26.74.2.1108016)
[![DOI](https://img.shields.io/badge/DOI-10.46904%2Feea.26.74.2.1108016-blue.svg)](https://doi.org/10.46904/eea.26.74.2.1108016)
[![Hardware](https://img.shields.io/badge/Hardware-Analog%20AFE%20%2B%20Arduino-orange.svg)](#hardware--circuit-summary)
[![Signal-to-Noise](https://img.shields.io/badge/Max%20SNR-32.5%20dB-brightgreen.svg)](#matlab-dsp--signal-quality)
[![Tests](https://img.shields.io/badge/Tests-100%25%20Passing-success.svg)](#how-to-run)

**Peer-Reviewed Publication**  
Authors: Abdulaziz K.A. Hatem, Ahmed M.A.S. AlKadhi, Mohammed A A. Qasem, Khaled A.M. Farhan, and Nasr Kaid Ali AL-Audi  
*Electrotehnică, Electronică, Automatică (EEA)*, 2026, vol. 74, no. 2, pp. 130–137. ISSN 1582-5175.  
Department of Biomedical Engineering, Faculty of Engineering, University of Science and Technology, Aden, Yemen.

---

## Overview

Electrooculography (EOG) records the standing electrical dipole of the human eye—the **cornea-retinal potential (CRP)**—which generates biopotentials between $50\,\mu\text{V}$ and $3500\,\mu\text{V}$. When the subject blinks or moves their eyes, this dipole shifts relative to surface electrodes, producing detectable voltage variations.

This repository provides the complete open-source hardware and software implementation of our low-cost (< $15 USD) analog EOG acquisition platform. Designed as an undergraduate biomedical engineering graduation project and subsequently published in the *EEA Journal*, the system captures vertical eye movements and blinks to serve as the control interface for assistive technologies, such as a smart wheelchair and an Arabic virtual keyboard.

> For full theoretical derivations, clinical protocols, and extensive multi-subject statistical tables, please consult our published paper:  
> [DOI: 10.46904/eea.26.74.2.1108016](https://doi.org/10.46904/eea.26.74.2.1108016).

---

## Hardware & Circuit Summary

The analog front-end (AFE) conditions microvolt-level ocular biopotentials through dedicated analog stages before digitization:

```
[ Ag/AgCl Electrodes ] ──► [ Stage 1: AD620 Pre-Amp (Gain = 495×, CMRR > 100 dB) ]
                       ──► [ Stage 2: Active Bandpass 1.6–16 Hz (Inverting Gain = 10×) ]
                       ──► [ Stage 3: Active Lowpass 16 Hz (Gain = 2×) ]
                       ──► [ Stage 4: Variable Gain (2×–10×) & Level Shifter (0–5V) ]
                       ──► [ Arduino Uno ADC (10-bit, fs = 250 Hz) ] ──► [ MATLAB DSP ]
```

- **Instrumentation Pre-Amplifier**: AD620AN with external resistor $R_G = 100\,\Omega$ yields a fixed gain of $495\times$. High input impedance ($10\,\text{G}\Omega$) and high CMRR ($>100\,\text{dB}$) suppress common-mode noise.
- **Active Bandpass Filter**: Second-order active bandpass ($1.6\,\text{Hz} - 16\,\text{Hz}$) using TL072/LM741 op-amps with $10\times$ inverting gain removes baseline DC drift and high-frequency EMG noise.
- **Active Low-Pass Filter**: Additional low-pass stage at $f_c = 16\,\text{Hz}$ ($2\times$ gain) sharpens roll-off against residual powerline hum.
- **Variable Gain & DC Level Shifter**: Trimmer potentiometer ($2\times - 10\times$) followed by a voltage divider DC level shifter centers the bipolar signal into the $0 - 5\,\text{V}$ unipolar window for the Arduino ADC.
- **Subject Safety & Power**: Powered by two 9V batteries ($\pm 9\,\text{V}$, virtual ground), providing 100% galvanic isolation from the AC electrical grid.
- **Electrode Placement**: Standard vertical channel using disposable Ag/AgCl pediatric gel electrodes:
  - $(V+)$: Superior orbital rim (above eyebrow).
  - $(V-)$: Inferior orbital rim (below lower eyelid).
  - $(\text{REF})$: Forehead center (electrical ground).

---

## Hardware Schematics & Photos

### Circuit Schematic
Full CAD schematic layout developed in KiCad 9:
![EOG Circuit Schematic](assets/hardware/eog_circuit_schematic.png)

### Electrode Montage on Subject
Pediatric Ag/AgCl surface electrodes placed on a research participant for vertical EOG acquisition:
![Electrode Placement Setup](assets/hardware/electrode_placement_setup.jpeg)

### Complete Testbench Setup
Laboratory bench setup during live testing: breadboard analog circuit, dual 9V batteries, Arduino Uno, Hantek DSO5072P oscilloscope, and host laptop running real-time MATLAB acquisition:
![Full Laboratory Test Setup](assets/hardware/full_test_setup.jpeg)

---

## Analog Validation & Video Demo

### Powerline Mains Hum (Pre-Filtering)
During initial testing directly after the AD620 pre-amplifier, the unconditioned signal exhibited significant 50 Hz powerline interference:

![50 Hz Mains Interference](assets/oscilloscope/50hz_mains_interference.jpeg)  
*Oscilloscope capture (400 ms/div, 500 mV/div) showing severe 50 Hz powerline hum riding on the raw signal prior to active filtering.*

### Hardware Filtering & Live Demonstration
Our active bandpass and low-pass stages completely clean this 50 Hz hum in the analog domain before digital sampling. While an isolated still photo of the filtered trace was not kept, the stable, noise-free analog waveform is visible on the oscilloscope screen in the bench photo above and is demonstrated live in the video below.

[![Watch the EOG Live Demo](https://img.shields.io/badge/YouTube-Live%20Analog%20EOG%20Demo-red?style=for-the-badge&logo=youtube)](https://youtu.be/ZO9QT6c9rzA)

> **Live Video Demonstration**: [Watch Abdulaziz Hatem demonstrate the live analog EOG signal on YouTube](https://youtu.be/ZO9QT6c9rzA).  
> The video shows the real-time analog signal responding cleanly to vertical eye movements and voluntary blinks on the oscilloscope before any microcontroller software filtering.

---

## MATLAB DSP & Signal Quality

The Arduino Uno streams 10-bit ADC samples at $250\,\text{Hz}$ ($115200\,\text{bps}$) to MATLAB, where lightweight DSP filters polish the waveform:
1. **3-sample Moving Average**: Eliminates ADC quantization jitter.
2. **150-sample Moving Average**: Tracks and subtracts baseline wander.
3. **10th-Order Butterworth Notch Filter**: Targets residual 50 Hz interference.
4. **7-sample Moving Average**: Delivers smooth peak detection for event discrimination.

![Representative Clean Filtered EOG Waveform](assets/matlab_dsp/matlab_filtered_comparison.png)  
*Filtered EOG waveform in MATLAB across experimental phases, demonstrating clear distinction between resting baseline, voluntary blinks, and gaze deflections.*

- **High Signal-to-Noise Ratio**: Achieves a peak SNR of **32.5 dB** during voluntary blinks ($V_{pp} = 13.58\,\text{V}$ vs. baseline noise $0.39\,\text{V}$ on the display scale).
- **Signal Power**: Signal power is $> 1,600\times$ higher than background resting noise, ensuring zero false triggers in assistive control applications.

---

## How to Run

### 1. Arduino Firmware
- Connect the analog circuit output to pin `A0` of an Arduino Uno.
- Open [`src/arduino/eog_acquisition.ino`](src/arduino/eog_acquisition.ino) (or [`src/arduino/eog_acquisition/eog_acquisition.ino`](src/arduino/eog_acquisition/eog_acquisition.ino)) in the Arduino IDE.
- Select your board and port, then click **Upload** (baud rate: `115200`).

### 2. MATLAB Real-Time Acquisition & GUI
- Open MATLAB (R2020b or later).
- In [`src/matlab/eog_realtime_acquisition.m`](src/matlab/eog_realtime_acquisition.m), configure your Arduino COM port:
  ```matlab
  port = 'COM3'; % Adjust to your system's serial port
  ```
- Run the script to start live acquisition, real-time filtering, and the interactive assistive interface.

### 3. Running Automated Tests
The repository includes an automated DSP and finite-state machine (FSM) test suite:
```matlab
run('tests/test_eog_pipeline.m')
```
*Tests verify notch filter stability, ADC voltage scaling, streaming recursion, blink vs. gaze discrimination, Arabic keyboard mapping, and wheelchair FSM transitions (6/6 tests passing).*

---

## Repository Structure

```
eog-acquisition-platform/
├── README.md                                # Project documentation
├── .gitignore                               # Git ignore rules
├── src/
│   ├── arduino/
│   │   ├── eog_acquisition.ino              # Arduino sketch (250 Hz ADC biopotential acquisition)
│   │   ├── eog_acquisition/
│   │   │   └── eog_acquisition.ino          # Arduino IDE sketch format
│   │   ├── wheelchair_controller.ino        # Assistive wheelchair robot firmware
│   │   └── wheelchair_controller/
│   │       └── wheelchair_controller.ino    # Arduino IDE sketch format
│   └── matlab/
│       ├── eog_realtime_acquisition.m       # Real-time serial acquisition, DSP filtering & GUI
│       └── eog_signal_analysis.m            # Signal quality evaluation & statistical analysis
├── tests/
│   └── test_eog_pipeline.m                  # Automated DSP & FSM unit test suite
└── assets/
    ├── hardware/
    │   ├── eog_circuit_schematic.png        # Analog front-end circuit schematic (KiCad)
    │   ├── electrode_placement_setup.jpeg   # Subject electrode placement
    │   └── full_test_setup.jpeg             # Laboratory bench test setup
    ├── oscilloscope/
    │   └── 50hz_mains_interference.jpeg     # Raw oscilloscope trace with 50 Hz mains noise
    └── matlab_dsp/
        └── matlab_filtered_comparison.png   # Filtered EOG waveform output in MATLAB
```

---

## Related Projects

- **[eog-assistive-hci-keyboard](https://github.com/Abdulaziz-kh-Hatem/eog-assistive-hci-keyboard)**: Complete eye-controlled Arabic virtual speller and smart wheelchair navigation system based on this acquisition platform (Awarded 100% Graduation Distinction).
- **[ecg-acquisition-platform](https://github.com/Abdulaziz-kh-Hatem/ecg-acquisition-platform)**: Low-cost ECG biopotential analog front-end and acquisition system for cardiovascular telemetry.

---

## Citation

If you use this circuit design, firmware, or signal processing pipeline, please cite our peer-reviewed journal paper:

```bibtex
@article{hatem2026eog,
  title   = {Design and Development of a Low-Cost Electronic Platform for Electrooculography Signals Acquisition},
  author  = {Hatem, Abdulaziz K.A. and AlKadhi, Ahmed M.A.S. and Qasem, Mohammed A A. and Farhan, Khaled A.M. and AL-Audi, Nasr Kaid Ali},
  journal = {Electrotehnic\u{a}, Electronic\u{a}, Automatic\u{a} (EEA)},
  volume  = {74},
  number  = {2},
  pages   = {130--137},
  year    = {2026},
  issn    = {1582-5175},
  doi     = {10.46904/eea.26.74.2.1108016}
}
```

> Abdulaziz K.A. Hatem, Ahmed M.A.S. AlKadhi, Mohammed A A. Qasem, Khaled A.M. Farhan, Nasr Kaid Ali AL-Audi, *"Design and Development of a Low-Cost Electronic Platform for Electrooculography Signals Acquisition"*, **Electrotehnică, Electronică, Automatică (EEA)**, 2026, vol. 74, no. 2, pp. 130–137. ISSN 1582-5175. DOI: [10.46904/eea.26.74.2.1108016](https://doi.org/10.46904/eea.26.74.2.1108016).
