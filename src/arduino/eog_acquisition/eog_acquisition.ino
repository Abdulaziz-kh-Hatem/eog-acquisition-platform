/*
 * EOG Signal Acquisition Firmware
 * Project: Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition
 * Hardware: Arduino Uno (ATmega328P), 10-bit ADC, UART Serial @ 115200 bps
 * 
 * Description:
 * Samples the conditioned analog biopotential signal from the Analog Front-End (AFE)
 * circuit on analog pin A0 at a constant 250 Hz sampling rate (4000 us interval)
 * and transmits raw ADC counts (0 - 1023) over USB-serial to the MATLAB host.
 * 
 * Timing:
 * Uses a non-blocking micros() timer loop to eliminate cumulative timing drift
 * without blocking execution via delay().
 */

// Hardware pin and sampling configuration
const int EOG_INPUT_PIN = A0;                   // Analog input pin connected to AFE output
const unsigned long SAMPLE_INTERVAL_US = 4000;  // 4000 us = 4.0 ms interval -> fs = 250 Hz
const long SERIAL_BAUD_RATE = 115200;           // High baud rate to minimize UART transmission latency

// Timing tracking variable
unsigned long previousMicros = 0;

void setup() {
  // Initialize serial communication with PC
  Serial.begin(SERIAL_BAUD_RATE);
  
  // Ensure default 5V ADC reference voltage (ATmega328P 10-bit ADC: 4.88 mV / LSB)
  analogReference(DEFAULT);
  
  // Seed timer base
  previousMicros = micros();
}

void loop() {
  unsigned long currentMicros = micros();
  
  // Non-blocking 250 Hz interval check
  if (currentMicros - previousMicros >= SAMPLE_INTERVAL_US) {
    // Advance base timestamp by fixed interval to avoid cumulative drift
    previousMicros += SAMPLE_INTERVAL_US;
    
    // Read 10-bit ADC value (0 to 1023, representing 0 to 5.0 V)
    int adcValue = analogRead(EOG_INPUT_PIN);
    
    // Transmit integer sample followed by newline (\r\n) for readline() in MATLAB
    Serial.println(adcValue);
  }
}
