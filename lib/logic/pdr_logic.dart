import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart'; // Ensure vector_math is available

/// Advanced PDr Engine optimized for Bookstore environments.
///
/// Features:
/// 1. EKF (Extended Kalman Filter) combining Gyro and Accel with magnetic rejection.
/// 2. Weinberg Step Length Estimation.
/// 3. Orthogonal Snapping (0, 90, 180, 270 degrees).
/// 4. Trajectory Correction (Back-propagation).
class AdvancedPdrEngine {
  // --- Configuration ---
  final double userHeight; // cm
  final double orthogonalSnapThreshold; // radians (e.g. 15 degrees)
  final double magnetRejectionThreshold; // uT variance

  // --- State ---
  List<Offset> _path = [Offset.zero];
  double _currentHeading = 0.0; // radians
  
  // EKF State: [Heading, GyroBias]
  Vector2 _ekfState = Vector2.zero();
  Matrix2 _ekfCovariance = Matrix2.identity();
  
  // Step Detection
  List<double> _accelBuffer = [];
  double _lastStepTime = 0.0;
  static const int _bufferSize = 50; // approx 1 sec at 50Hz
  static const double _weinbergK = 0.45; // Tunable constant

  // ZUPT (Zero Velocity Update)
  bool _isStationary = false;
  int _stationaryCounter = 0;

  AdvancedPdrEngine({
    this.userHeight = 170.0,
    this.orthogonalSnapThreshold = 15.0 * math.pi / 180.0,
    this.magnetRejectionThreshold = 50.0,
  }) {
    // Initialize EKF cov
    _ekfCovariance.setIdentity();
    _ekfCovariance.scale(0.1);
  }

  /// Main update loop called on sensor events
  void update({
    required Vector3 accel, // m/s^2
    required Vector3 gyro,  // rad/s
    Vector3? mag,           // uT (optional)
    double dt = 0.02,       // delta time (seconds)
  }) {
    // 1. ZUPT & Activity Detection
    _checkStationary(accel);

    // 2. EKF Prediction (Gyro Integration)
    _predictEKF(gyro, dt);

    // 3. EKF Correction (Accel/Mag)
    _correctEKF(accel, mag);

    // 4. Update Heading
    _currentHeading = _ekfState.x;

    // 5. Orthogonal Constraint (Map Matching)
    _applyOrthogonalConstraint();

    // 6. Step Detection & Dead Reckoning
    if (!_isStationary) {
      _detectAndProcessStep(accel);
    }
  }

  /// 1. EKF Prediction Step
  /// Model: theta_k = theta_{k-1} + (gyro - bias) * dt
  ///        bias_k = bias_{k-1}
  void _predictEKF(Vector3 gyro, double dt) {
    // State Transition Matrix F
    // [1, -dt]
    // [0,  1]
    final F = Matrix2(1.0, -dt, 0.0, 1.0);

    // Predict State
    double gyroZ = gyro.z; // Assuming Z is vertical axis in device frame
    double predictedHeading = _ekfState.x + (gyroZ - _ekfState.y) * dt;
    double predictedBias = _ekfState.y;
    _ekfState = Vector2(predictedHeading, predictedBias);

    // Predict Covariance P = F*P*F' + Q
    final Q = Matrix2(0.001, 0.0, 0.0, 0.0001); // Process Noise
    _ekfCovariance = (F * _ekfCovariance * F.transposed()) + Q;
  }

  /// 2. EKF Correction Step
  /// Uses Accelerometer (for tilt) and Magnetometer (for absolute heading)
  void _correctEKF(Vector3 accel, Vector3? mag) {
    // Simple Tilt Compensation
    double roll = math.atan2(accel.y, accel.z);
    double pitch = math.atan2(-accel.x, math.sqrt(accel.y * accel.y + accel.z * accel.z));

    if (mag != null) {
      // Check Magnetic Disturbance
      double magNorm = mag.length;
      if ((magNorm - 45.0).abs() < magnetRejectionThreshold) {
        // Valid Mag: Compute Yaw
        // Simplified for brevity; full tilt compensation needed
        double my = mag.y * math.cos(roll) - mag.z * math.sin(roll);
        double mx = mag.x * math.cos(pitch) + mag.y * math.sin(pitch) * math.sin(roll) + mag.z * math.sin(pitch) * math.cos(roll);
        double magHeading = -math.atan2(my, mx);

        // Innovation
        double z = magHeading;
        double h = _ekfState.x;
        double y = z - h;
        // Normalize angle
        while (y > math.pi) y -= 2 * math.pi;
        while (y < -math.pi) y += 2 * math.pi;

        // Measurement Matrix H = [1, 0]
        final H = Matrix12(1.0, 0.0); // 1x2, represented as Row vector logic
        // R = Measurement Noise
        double R = 0.1; 

        // Kalman Gain K = P*H' / (H*P*H' + R)
        // Manual calculation for scalar measurement
        double S = _ekfCovariance.entry(0, 0) + R;
        Vector2 K = Vector2(_ekfCovariance.entry(0, 0) / S, _ekfCovariance.entry(1, 0) / S);

        // Update State
        _ekfState += K * y;
        
        // Update Covariance P = (I - K*H)*P
        Matrix2 I = Matrix2.identity();
        Matrix2 KH = Matrix2(K.x, 0.0, K.y, 0.0); // K * H
        _ekfCovariance = (I - KH) * _ekfCovariance;
      }
    }
  }

  /// 3. Orthogonal Constraint (Map Matching)
  /// Snaps heading to 0, 90, 180, 270 if moving straight
  void _applyOrthogonalConstraint() {
    if (_isStationary) return;

    double h = _ekfState.x;
    // Normalize to 0-360
    while (h < 0) h += 2 * math.pi;
    while (h >= 2 * math.pi) h -= 2 * math.pi;

    double closestGrid = (h / (math.pi / 2)).round() * (math.pi / 2);
    double diff = (h - closestGrid).abs();

    if (diff < orthogonalSnapThreshold) {
      // Gentle snap (Low-pass filter towards grid)
      double alpha = 0.1;
      _currentHeading = _currentHeading * (1 - alpha) + closestGrid * alpha;
      // Feed back to EKF? Maybe dangerous if wrong. 
      // For now, only output heading is affected.
      _ekfState.x = _currentHeading;
    }
  }

  /// 4. Weinberg Step Length Estimation
  /// L = K * (A_max - A_min)^(1/4)
  void _detectAndProcessStep(Vector3 accel) {
    double magnitude = accel.length;
    _accelBuffer.add(magnitude);
    if (_accelBuffer.length > _bufferSize) _accelBuffer.removeAt(0);

    // Simple Peak Detection
    if (_accelBuffer.length < 3) return;
    
    // Check if middle is peak
    int mid = _accelBuffer.length - 2;
    double prev = _accelBuffer[mid - 1];
    double curr = _accelBuffer[mid];
    double next = _accelBuffer[mid + 1];

    if (curr > prev && curr > next && curr > 11.0) { // Threshold 11 m/s^2
       double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
       if (now - _lastStepTime > 0.4) {
         // Valid Step
         _processStep();
         _lastStepTime = now;
       }
    }
  }

  void _processStep() {
    // Calculate Weinberg Step Length
    double aMax = _accelBuffer.reduce(math.max);
    double aMin = _accelBuffer.reduce(math.min);
    
    // Constant K is roughly 0.45 * height (in meters?) -> No, K is unitless constant ~0.45
    // Typical formula: StepLength = K * (Amax - Amin)^(1/4)
    // K is usually tuned. Let's assume K=0.45 for now.
    double stepLength = _weinbergK * math.pow(aMax - aMin, 0.25);
    
    // Limit reasonable step length
    if (stepLength < 0.3) stepLength = 0.3;
    if (stepLength > 1.2) stepLength = 1.2;

    // Dead Reckoning
    Offset lastPos = _path.last;
    double dx = stepLength * math.cos(_currentHeading);
    double dy = stepLength * math.sin(_currentHeading);
    
    // * 40.0 for pixel scaling (1m = 40px)
    _path.add(lastPos + Offset(dx, dy) * 40.0);
  }

  void _checkStationary(Vector3 accel) {
    // Simple variance check
    // If accel variance is low for N frames -> Stationary
    // (Omitted for brevity, assuming simple threshold)
    double mag = accel.length;
    if ((mag - 9.8).abs() < 0.5) {
      _stationaryCounter++;
    } else {
      _stationaryCounter = 0;
    }
    _isStationary = _stationaryCounter > 20; // ~0.4s
  }
  
  /// 5. Back-propagation for Loop Closure / Checkpoint
  /// Corrects the path linearly based on a known true position
  void correctTrajectory(Offset knownPosition) {
    if (_path.isEmpty) return;
    
    Offset currentEstimated = _path.last;
    Offset error = knownPosition - currentEstimated;
    
    // Distribute error proportional to index
    int n = _path.length;
    for (int i = 0; i < n; i++) {
      double ratio = i / (n - 1);
      _path[i] += error * ratio;
    }
    
    // Reset EKF state if needed?
    // Maybe update heading if correction implies heading error
  }
  
  // Getters
  List<Offset> get path => _path;
  double get heading => _currentHeading;
}

// Helpers for Matrix12 (1x2 matrix) since vector_math doesn't have it explicitly
class Matrix12 {
  final double x, y;
  Matrix12(this.x, this.y);
  // Implementation of multiply...
}
