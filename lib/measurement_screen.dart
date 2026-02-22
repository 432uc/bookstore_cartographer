import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoding/geocoding.dart';
import 'database_helper.dart';
import 'models/bookstore.dart';

class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  // PDR (Pedestrian Dead Reckoning) 状態
  List<Offset> _path = [Offset(0, 0)];
  double _currentHeading = 0.0;
  int _lastSentSteps = 0;
  int _totalSteps = 0;
  double _stepLength = 0.7; // 推定歩幅 (メートル)
  
  // センサー用サブスクリプション
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  // 加速度センサーによる歩行検出
  List<double> _accelerationMagnitudes = [];
  double _lastPeakTime = 0;
  static const double _stepThreshold = 2.5; // 歩行検出の閾値 (感度を上げる)
  static const double _minStepInterval = 0.4; // 最小歩行間隔（秒）

  // UI状態
  bool _isMeasuring = false;
  bool _showCorrectionMode = false;
  List<int> _selectedIndices = [];
  String _error = "";
  String _sensorStatus = "待機中";

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.activityRecognition.request();
    if (status.isDenied) {
      setState(() => _error = "身体活動の許可が必要です");
    }
  }

  Future<void> _startListening() async {
    await _checkPermissions();
    
    _path = [Offset(0, 0)]; // リセット
    _lastSentSteps = 0;
    _totalSteps = 0;
    _accelerationMagnitudes.clear();
    _lastPeakTime = 0;
    
    setState(() {
      _sensorStatus = "センサー初期化中...";
    });

    // 方位の取得 (改善版コンパス)
    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      if (mounted) {
        setState(() {
          // より正確な方位計算（デバイスを垂直に持つ場合も考慮）
          double heading = math.atan2(event.y, event.x);
          // 簡易的なローパスフィルタで揺れを抑制
          _currentHeading = _currentHeading * 0.8 + heading * 0.2;
          // _sensorStatus = "コンパス: ${(_currentHeading * 180 / math.pi).toStringAsFixed(0)}°";
        });
      }
    }, onError: (e) {
      setState(() => _sensorStatus = "コンパスエラー: $e");
      debugPrint("Magnetometer error: $e");
    });

    // 歩数計（ハードウェアセンサー）- ログ用としてのみ使用
    _stepCountSubscription = Pedometer.stepCountStream.listen((event) {
      debugPrint("Pedometer steps (hardware): ${event.steps}");
      // ハードウェア歩数計は反応が遅いため、今回はログ出力のみにとどめ、
      // 実際の経路描画は加速度センサーリアルタイム検出を使用する
      /*
      if (_lastSentSteps == 0) {
        _lastSentSteps = event.steps;
      } else if (event.steps > _lastSentSteps) {
        int diff = event.steps - _lastSentSteps;
        for (int i = 0; i < diff; i++) {
          _onStepDetected();
        }
        _lastSentSteps = event.steps;
        setState(() => _sensorStatus = "歩数計: ${_totalSteps}歩");
      }
      */
    }, onError: (e) {
      debugPrint("Pedometer error: $e");
    });

    // 加速度センサーによる歩行検知 (即時反応のためこちらをメインに使用)
    _startAccelerometerDetection();
  }

  void _startAccelerometerDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (!_isMeasuring) return;
      
      // 加速度の大きさを計算
      double magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z
      );
      
      _accelerationMagnitudes.add(magnitude);
      
      // 最新100サンプルのみ保持
      if (_accelerationMagnitudes.length > 100) {
        _accelerationMagnitudes.removeAt(0);
      }

      // ピーク検出（歩行判定）
      if (_accelerationMagnitudes.length > 10) {
        double current = _accelerationMagnitudes.last;
        double avg = _accelerationMagnitudes.reduce((a, b) => a + b) / _accelerationMagnitudes.length;
        
        double now = DateTime.now().millisecondsSinceEpoch / 1000.0;
        
        // ピーク検出: 平均より大きく、閾値を超え、前回から一定時間経過
        if (current > avg + _stepThreshold && 
            (now - _lastPeakTime) > _minStepInterval) {
          _lastPeakTime = now;
          _onStepDetected();
          debugPrint("Accelerometer step detected: magnitude=$magnitude");
        }
      }
    });
  }

  void _stopListening() {
    _magnetometerSubscription?.cancel();
    _stepCountSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _magnetometerSubscription = null;
    _stepCountSubscription = null;
    _accelerometerSubscription = null;
  }

  void _onStepDetected() {
    if (!mounted) return;
    
    debugPrint("=== STEP DETECTED ===");
    debugPrint("Total steps: ${_totalSteps + 1}");
    debugPrint("Current heading: $_currentHeading radians (${(_currentHeading * 180 / math.pi).toStringAsFixed(1)}°)");
    debugPrint("Current path length: ${_path.length}");
    
    setState(() {
      _totalSteps++;
      // 現在の方位に向かって歩行 (1m = 40px にスケーリングして見やすく)
      double scale = 40.0;
      // 方位の補正 (デバイスの向きに応じて調整が必要な場合がある)
      double dx = math.cos(_currentHeading) * _stepLength * scale;
      double dy = math.sin(_currentHeading) * _stepLength * scale;
      
      Offset lastPos = _path.last;
      Offset newPos = Offset(lastPos.dx + dx, lastPos.dy + dy);
      _path.add(newPos);
      
      debugPrint("New position: (${newPos.dx.toStringAsFixed(1)}, ${newPos.dy.toStringAsFixed(1)})");
      debugPrint("Path now has ${_path.length} points");
      
      // センサー状態を更新
      _sensorStatus = "歩数: ${_totalSteps} | 方位: ${(_currentHeading * 180 / math.pi).toStringAsFixed(0)}°";
    });
  }

  // 直線補正ロジック: 選択した2点間を直線にする
  void _applyCorrection() {
    if (_selectedIndices.length != 2) return;
    
    _selectedIndices.sort();
    int startIdx = _selectedIndices[0];
    int endIdx = _selectedIndices[1];
    
    Offset start = _path[startIdx];
    Offset end = _path[endIdx];
    
    List<Offset> newPath = [];
    // 開始点まで
    for (int i = 0; i <= startIdx; i++) newPath.add(_path[i]);
    
    // 開始から終了までを直線で補間
    int steps = endIdx - startIdx;
    for (int i = 1; i < steps; i++) {
        double t = i / steps;
        newPath.add(Offset(
            start.dx + (end.dx - start.dx) * t,
            start.dy + (end.dy - start.dy) * t
        ));
    }
    
    // 終了点以降
    for (int i = endIdx; i < _path.length; i++) newPath.add(_path[i]);

    setState(() {
      _path = newPath;
      _selectedIndices.clear();
    });
  }

  // 面積算出 (靴紐の公式)
  double _calculateArea() {
    if (_path.length < 3) return 0;
    double area = 0.0;
    for (int i = 0; i < _path.length; i++) {
      int j = (i + 1) % _path.length;
      area += _path[i].dx * _path[j].dy;
      area -= _path[j].dx * _path[i].dy;
    }
    // スケール還元 (20px = 1m なので、面積は 400px^2 = 1m^2)
    return (area.abs() / 2.0) / 400.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // ダークプレミアムな背景
      body: Stack(
        children: [
          // 軌跡描画エリア
          GestureDetector(
            onTapDown: (details) {
              if (_showCorrectionMode) {
                // 最寄りの点を選択
                int nearestIdx = -1;
                double minDist = 50.0;
                for (int i = 0; i < _path.length; i++) {
                  double d = (_path[i] + Offset(MediaQuery.of(context).size.width/2, MediaQuery.of(context).size.height/2) - details.localPosition).distance;
                  if (d < minDist) {
                    minDist = d;
                    nearestIdx = i;
                  }
                }
                if (nearestIdx != -1) {
                  setState(() {
                    if (_selectedIndices.contains(nearestIdx)) {
                      _selectedIndices.remove(nearestIdx);
                    } else if (_selectedIndices.length < 2) {
                      _selectedIndices.add(nearestIdx);
                    }
                  });
                }
              }
            },
            child: CustomPaint(
              painter: PathPainter(
                path: _path, 
                selectedIndices: _selectedIndices,
                isCorrectionMode: _showCorrectionMode
              ),
              size: Size.infinite,
            ),
          ),
          
          // UIオーバーレイ
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(),
                  const Spacer(),
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isMeasuring ? "計測中..." : "待機中",
            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
          ),
          if (_sensorStatus.isNotEmpty)
            Text(
              _sensorStatus,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          if (_error.isNotEmpty)
            Text(
              _error,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statusItem("歩数", "${_totalSteps}歩"),
              _statusItem("距離", "${(_totalSteps * _stepLength).toStringAsFixed(1)}m"),
              _statusItem("面積", "${_calculateArea().toStringAsFixed(1)}㎡"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _circleButton(
              icon: _isMeasuring ? Icons.stop : Icons.play_arrow,
              label: _isMeasuring ? "停止" : "開始",
              color: _isMeasuring ? Colors.redAccent : Colors.greenAccent,
              onTap: () {
                setState(() {
                  _isMeasuring = !_isMeasuring;
                  if (_isMeasuring) {
                    _startListening();
                  } else {
                    _stopListening();
                  }
                });
              },
            ),
            _circleButton(
              icon: Icons.add,
              label: "手動",
              color: Colors.cyanAccent,
              onTap: () {
                if (_isMeasuring) _onStepDetected();
              },
            ),
            _circleButton(
              icon: Icons.refresh,
              label: "リセット",
              color: Colors.orangeAccent,
              onTap: () {
                setState(() {
                  _path = [Offset(0, 0)];
                  _totalSteps = 0;
                  _selectedIndices.clear();
                });
              },
            ),
          ],
        ),
        if (_totalSteps >= 3 && !_isMeasuring)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ElevatedButton.icon(
              onPressed: _saveMeasurement,
              icon: const Icon(Icons.save),
              label: const Text("計測結果を保存"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _saveMeasurement() async {
    if (_path.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最低3点以上の計測が必要です')),
      );
      return;
    }

    try {
      // 現在地と住所を取得
      final locationService = loc.Location();
      final locationData = await locationService.getLocation();
      
      String address = "PDR Measured Location";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          locationData.latitude!, 
          locationData.longitude!
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          address = "${place.administrativeArea}${place.locality}${place.street}";
        }
      } catch (_) {}

      // 座標データをJSON保存
      final pathData = jsonEncode(_path.map((v) => {'x': v.dx, 'y': v.dy}).toList());
      final area = _calculateArea();

      final newStore = Bookstore(
        name: "PDR計測本屋 ${DateTime.now().hour}:${DateTime.now().minute}",
        station: "",
        registers: 0,
        hasToilet: false,
        hasCafe: false,
        address: address,
        pathData: pathData,
        area: area,
      );

      await DatabaseHelper.instance.insertStore(newStore);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('計測結果を保存しました (面積: ${area.toStringAsFixed(1)}㎡)')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Save error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存エラー: $e')),
        );
      }
    }
  }

  Widget _circleButton({
    required IconData icon, 
    required Color color, 
    required VoidCallback onTap,
    String? label,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}

class PathPainter extends CustomPainter {
  final List<Offset> path;
  final List<int> selectedIndices;
  final bool isCorrectionMode;

  PathPainter({required this.path, required this.selectedIndices, required this.isCorrectionMode});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()..style = PaintingStyle.fill;

    if (path.length < 2) return;

    final drawPath = Path();
    drawPath.moveTo(path[0].dx + center.dx, path[0].dy + center.dy);

    for (int i = 1; i < path.length; i++) {
      drawPath.lineTo(path[i].dx + center.dx, path[i].dy + center.dy);
    }

    // グリッド線の描画 (背景)
    _drawGrid(canvas, size);

    // 軌跡の描画
    canvas.drawPath(drawPath, paint);

    // 補正モード時の点の表示
    if (isCorrectionMode) {
      for (int i = 0; i < path.length; i++) {
        dotPaint.color = selectedIndices.contains(i) ? Colors.orange : Colors.white30;
        canvas.drawCircle(path[i] + center, selectedIndices.contains(i) ? 6 : 3, dotPaint);
      }
    }
    
    // 現在地 (先端)
    dotPaint.color = Colors.redAccent;
    canvas.drawCircle(path.last + center, 6, dotPaint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 1;
    double step = 20.0; // 1m間隔
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
