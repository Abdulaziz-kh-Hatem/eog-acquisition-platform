/*
 * Embedded Firmware for 3D-Printed Prototype Wheelchair Navigation
 * Project: Low-Cost Electronic Platform for Electrooculography (EOG) Signals Acquisition
 * Target Hardware: Arduino Uno (ATmega328P), L298N Dual H-Bridge Driver, HC-05 Bluetooth, Dual HC-SR04
 * 
 * Description:
 * Receives directional motion commands ('1'=Forward, '2'=Stop, '3'=Backward, '4'=Rotate)
 * sent over Bluetooth from the MATLAB EOG real-time controller.
 * Drives two DC geared motors via L298N H-bridge with PWM speed control.
 * Features an active safety system polling front and rear ultrasonic distance sensors
 * every 40 ms to detect obstacles, automatically stopping motors and sounding an alert buzzer.
 */

// =========================================================================
// 1. Motor Speed, Delay, and Safety Threshold Constants
// =========================================================================
const int linearSpeed   = 120;   // Forward and backward PWM duty cycle (0 - 255)
const int rotationSpeed = 100;   // Differential steering yaw rotation PWM duty cycle (0 - 255)
const int stopDelayTime = 1500;  // Pause duration (ms) upon obstacle alert before evasive maneuver

const int FRONT_OBSTACLE_THRESHOLD_CM = 40; // Front collision stopping distance (cm)
const int REAR_OBSTACLE_THRESHOLD_CM  = 30; // Rear collision stopping distance (cm)
const unsigned long SENSOR_POLL_INTERVAL_MS = 40; // Ultrasonic polling interval (40 ms = 25 Hz)

// =========================================================================
// 2. Pin Assignments
// =========================================================================
// L298N Dual H-Bridge Motor Driver
const int ENA = 5;   // Left motor PWM speed enable
const int IN1 = 8;   // Left motor directional input 1
const int IN2 = 9;   // Left motor directional input 2
const int ENB = 6;   // Right motor PWM speed enable
const int IN3 = 10;  // Right motor directional input 3
const int IN4 = 11;  // Right motor directional input 4

// Ultrasonic HC-SR04 Proximity Sensors & Acoustic Buzzer
const int FRONT_TRIG = 2;
const int FRONT_ECHO = 12;
const int REAR_TRIG  = 4;
const int REAR_ECHO  = 7;
const int BUZZER_PIN = 3;

// =========================================================================
// 3. System State Variables
// =========================================================================
char command;
char currentState = '2';             // Active directional state: '1'=FWD, '2'=STOP, '3'=BWD, '4'=ROT
unsigned long lastSensorUpdate = 0;  // Non-blocking timer base for ultrasonic polling

// Forward function declarations
void moveForwardPhysically();
void moveBackwardPhysically();
void rotateChair();
void stopMotors();
void checkObstacles();
long getDistance(int trigPin, int echoPin);

void setup() {
  // Configure motor driver pins as digital outputs
  pinMode(ENA, OUTPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENB, OUTPUT);
  pinMode(IN3, OUTPUT);
  pinMode(IN4, OUTPUT);

  // Configure ultrasonic sensor and buzzer pins
  pinMode(FRONT_TRIG, OUTPUT);
  pinMode(FRONT_ECHO, INPUT);
  pinMode(REAR_TRIG, OUTPUT);
  pinMode(REAR_ECHO, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  // HC-05 Bluetooth transceiver UART interface (9600 bps default)
  Serial.begin(9600);

  // Start with all motors stopped for safety
  stopMotors();
}

void loop() {
  // Subsystem 1: Process incoming Bluetooth motion commands from MATLAB
  if (Serial.available() > 0) {
    command = Serial.read();

    // Validate and update directional state
    if (command == '1' || command == '2' || command == '3' || command == '4') {
      currentState = command;
    }

    switch (command) {
      case '1':
        // Drive forward
        moveForwardPhysically();
        Serial.println("Physical: Moving Forward");
        break;

      case '3':
        // Drive backward
        moveBackwardPhysically();
        Serial.println("Physical: Moving Backward");
        break;

      case '4':
        // Differential steering rotation
        rotateChair();
        Serial.println("Physical: Rotating...");
        break;

      case '2':
        // Stop motors
        stopMotors();
        Serial.println("Physical: Stopped");
        break;
    }
  }

  // Subsystem 2: Non-blocking obstacle avoidance check every 40 ms
  if (millis() - lastSensorUpdate >= SENSOR_POLL_INTERVAL_MS) {
    checkObstacles();
    lastSensorUpdate = millis();
  }
}

// =========================================================================
// 4. Ultrasonic Proximity Detection and Collision Avoidance
// =========================================================================
void checkObstacles() {
  // Check frontal obstacle when driving forward
  if (currentState == '1') {
    long frontDist = getDistance(FRONT_TRIG, FRONT_ECHO);
    if (frontDist > 0 && frontDist < FRONT_OBSTACLE_THRESHOLD_CM) {
      // 1. Immediate motor cutoff
      stopMotors();

      // 2. Sound acoustic alert buzzer
      digitalWrite(BUZZER_PIN, HIGH);
      delay(stopDelayTime);
      digitalWrite(BUZZER_PIN, LOW);

      // 3. Initiate evasive rotation
      currentState = '4';
      rotateChair();
    }
  }
  // Check rear obstacle when reversing
  else if (currentState == '3') {
    long rearDist = getDistance(REAR_TRIG, REAR_ECHO);
    if (rearDist > 0 && rearDist < REAR_OBSTACLE_THRESHOLD_CM) {
      // 1. Immediate motor cutoff
      stopMotors();

      // 2. Sound acoustic alert buzzer
      digitalWrite(BUZZER_PIN, HIGH);
      delay(stopDelayTime);
      digitalWrite(BUZZER_PIN, LOW);

      // 3. Transition to full stop
      currentState = '2';
    }
  }
}

// Measures distance via ultrasonic pulse time-of-flight with 8000 us timeout (~1.36 m range)
long getDistance(int trigPin, int echoPin) {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);

  // 8000 us timeout limits blocking duration to prevent interrupting the 40 ms cycle
  long duration = pulseIn(echoPin, HIGH, 8000);

  if (duration == 0) {
    return 999; // No echo received (target out of range)
  }

  // Distance in cm = (duration * speed of sound in air 0.034 cm/us) / 2 (round trip)
  return duration * 0.034 / 2;
}

// =========================================================================
// 5. L298N Dual H-Bridge Motor Actuation Routines
// =========================================================================

// Drive both motors forward
void moveForwardPhysically() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, HIGH);
  digitalWrite(IN4, LOW);

  analogWrite(ENA, linearSpeed);
  analogWrite(ENB, linearSpeed);
}

// Drive both motors backward
void moveBackwardPhysically() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);

  analogWrite(ENA, linearSpeed);
  analogWrite(ENB, linearSpeed);
}

// Differential yaw rotation (counter-rotating wheels)
void rotateChair() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, HIGH);

  analogWrite(ENA, rotationSpeed);
  analogWrite(ENB, rotationSpeed);
}

// Brake and cutoff power to both motors
void stopMotors() {
  analogWrite(ENA, 0);
  analogWrite(ENB, 0);

  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  digitalWrite(IN3, LOW);
  digitalWrite(IN4, LOW);
}
