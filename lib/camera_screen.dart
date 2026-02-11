import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as loc;
import 'database_helper.dart';
import 'models/bookstore.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final MediaStore _mediaStore = MediaStore();
  final loc.Location _locationService = loc.Location();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.cameras.first,
      ResolutionPreset.high,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takeAndSavePicture() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      debugPrint('Camera: Waiting for controller initialization...');
      await _initializeControllerFuture;

      // 1. 位置情報の権限と有効化チェック
      debugPrint('Camera: Checking location services...');
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          throw Exception('Location services are disabled.');
        }
      }

      debugPrint('Camera: Checking location permissions...');
      loc.PermissionStatus permissionGranted = await _locationService.hasPermission();
      if (permissionGranted == loc.PermissionStatus.denied) {
        permissionGranted = await _locationService.requestPermission();
        if (permissionGranted != loc.PermissionStatus.granted) {
          throw Exception('Location permissions are denied.');
        }
      }

      // 現在地を取得
      debugPrint('Camera: Getting current location...');
      final locationData = await _locationService.getLocation();
      debugPrint('Camera: Location acquired: ${locationData.latitude}, ${locationData.longitude}');

      // 2. 写真を撮影
      debugPrint('Camera: Taking picture...');
      final image = await _controller.takePicture();
      debugPrint('Camera: Picture taken: ${image.path}');

      // 3. ギャラリーへの保存
      debugPrint('Camera: Saving to gallery via MediaStore...');
      try {
        await _mediaStore.saveFile(
          tempFilePath: image.path, 
          dirType: DirType.photo, 
          dirName: DirName.pictures,
          relativePath: "bookstore_cartographer",
        );
        debugPrint('Camera: MediaStore save successful');
      } catch (e) {
        debugPrint('Camera: MediaStore save failed: $e');
        // 保存に失敗しても、撮影自体は進める（DB登録は試みる）
      }

      // 4. 現在地から住所を逆ジオコーディング
      debugPrint('Camera: Reverse geocoding...');
      String address = "Unknown Location";
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          locationData.latitude!, 
          locationData.longitude!
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          address = "${place.administrativeArea}${place.locality}${place.street}";
          debugPrint('Camera: Geocoded address: $address');
        }
      } catch (e) {
        debugPrint("Camera: Geocoding error: $e");
      }

      // 5. DBに自動登録
      debugPrint('Camera: Inserting into database...');
      final newBookstore = Bookstore(
        name: "Captured Store ${DateTime.now().hour}:${DateTime.now().minute}",
        station: "",
        registers: 0,
        hasToilet: false,
        hasCafe: false,
        address: address,
      );
      await DatabaseHelper.instance.insertStore(newBookstore);
      debugPrint('Camera: Database insertion complete');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存して登録しました: $address')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Camera: Fatal Error in _takeAndSavePicture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('写真を撮る')),
      body: Stack(
        children: [
          FutureBuilder<void>(
            future: _initializeControllerFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.done) {
                return CameraPreview(_controller);
              } else {
                return const Center(child: CircularProgressIndicator());
              }
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('保存中...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isProcessing 
        ? null 
        : FloatingActionButton(
            onPressed: _takeAndSavePicture,
            child: const Icon(Icons.camera_alt),
          ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
