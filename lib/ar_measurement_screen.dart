import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ar_flutter_plugin_flutterflow/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_flutterflow/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_node.dart';
import 'package:ar_flutter_plugin_flutterflow/models/ar_hittest_result.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'database_helper.dart';
import 'models/bookstore.dart';
import 'package:location/location.dart' as loc;
import 'package:geocoding/geocoding.dart';

class ARMeasurementScreen extends StatefulWidget {
  const ARMeasurementScreen({super.key});

  @override
  State<ARMeasurementScreen> createState() => _ARMeasurementScreenState();
}

class _ARMeasurementScreenState extends State<ARMeasurementScreen> {
  ARSessionManager? arSessionManager;
  ARObjectManager? arObjectManager;
  ARAnchorManager? arAnchorManager;
  ARLocationManager? arLocationManager;

  List<ARNode> nodes = [];
  List<ARAnchor> anchors = [];
  List<vector.Vector3> points = [];
  double totalArea = 0;
  bool isProcessing = false;

  @override
  void dispose() {
    arSessionManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AR高精度計測')),
      body: Stack(
        children: [
          ARView(
            onARViewCreated: onARViewCreated,
            planeDetectionConfig: PlaneDetectionConfig.horizontal,
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("ポイント数: ${points.length}", style: const TextStyle(color: Colors.white)),
                  Text("推定面積: ${totalArea.toStringAsFixed(2)} ㎡", 
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (isProcessing)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "save",
            onPressed: points.length >= 3 ? _saveMeasurement : null,
            backgroundColor: points.length >= 3 ? Colors.green : Colors.grey,
            child: const Icon(Icons.save),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "clear",
            onPressed: onRemoveEverything,
            backgroundColor: Colors.redAccent,
            child: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }

  void onARViewCreated(
      ARSessionManager arSessionManager,
      ARObjectManager arObjectManager,
      ARAnchorManager arAnchorManager,
      ARLocationManager arLocationManager) {
    this.arSessionManager = arSessionManager;
    this.arObjectManager = arObjectManager;
    this.arAnchorManager = arAnchorManager;
    this.arLocationManager = arLocationManager;

    this.arSessionManager!.onInitialize(
          showFeaturePoints: false,
          showPlanes: true,
          showWorldOrigin: false,
          handlePans: false,
          handleRotation: false,
        );
    this.arObjectManager!.onInitialize();

    this.arSessionManager!.onPlaneOrPointTap = onPlaneOrPointTapped;
  }

  Future<void> onRemoveEverything() async {
    for (var anchor in anchors) {
      arAnchorManager!.removeAnchor(anchor);
    }
    anchors = [];
    nodes = [];
    setState(() {
      points = [];
      totalArea = 0;
    });
  }

  Future<void> onPlaneOrPointTapped(List<ARHitTestResult> hitTestResults) async {
    var singleHitTestResult = hitTestResults.firstWhere(
        (hitTestResult) => hitTestResult.type == ARHitTestResultType.plane);
    
    var newAnchor = ARPlaneAnchor(transformation: singleHitTestResult.worldTransform);
    bool? didAddAnchor = await arAnchorManager!.addAnchor(newAnchor);
    if (didAddAnchor ?? false) {
      anchors.add(newAnchor);
      var newNode = ARNode(
          type: NodeType.webGLB,
          uri: "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Duck/glTF-Binary/Duck.glb", // Dummy small object
          scale: vector.Vector3(0.1, 0.1, 0.1),
          position: vector.Vector3(0, 0, 0),
          transformation: singleHitTestResult.worldTransform);
      
      // Instead of GLB, let's use a simple sphere if possible, but ar_flutter_plugin prefers GLB for nodes.
      // For measurement, we mostly care about the points.
      
      setState(() {
        // Extract translation from 4x4 matrix
        final translation = singleHitTestResult.worldTransform.getTranslation();
        points.add(translation);
        _calculateArea();
      });
    }
  }

  void _calculateArea() {
    if (points.length < 3) return;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      int j = (i + 1) % points.length;
      area += points[i].x * points[j].z;
      area -= points[j].x * points[i].z;
    }
    setState(() {
      totalArea = area.abs() / 2.0;
    });
  }

  Future<void> _saveMeasurement() async {
    if (points.isEmpty) return;
    setState(() => isProcessing = true);
    
    try {
      final locationService = loc.Location();
      final locationData = await locationService.getLocation();
      
      String address = "AR Measured Location";
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

      final pathData = jsonEncode(points.map((v) => {'x': v.x, 'y': v.y, 'z': v.z}).toList());

      final newStore = Bookstore(
        name: "AR測量本屋 ${DateTime.now().hour}:${DateTime.now().minute}",
        station: "",
        registers: 0,
        hasToilet: false,
        hasCafe: false,
        address: address,
        pathData: pathData,
        area: totalArea,
      );

      await DatabaseHelper.instance.insertStore(newStore);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AR計測結果を保存しました')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Save error: $e");
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }
}
