import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as loc;
import 'database_helper.dart';
import 'models/bookstore.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  MapScreenState createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  final loc.Location _locationService = loc.Location();

  @override
  void initState() {
    super.initState();
    loadBookstores();
  }

  Future<void> loadBookstores() async {
    final bookstores = await DatabaseHelper.instance.queryAllStores();
    _markers.clear();
    for (final bookstore in bookstores) {
      if (bookstore.address.isNotEmpty) {
        try {
          final locations = await locationFromAddress(bookstore.address);
          if (locations.isNotEmpty) {
            final location = locations.first;
            _addMarker(bookstore, LatLng(location.latitude, location.longitude));
          }
        } catch (e) {
          debugPrint("Geocoding error for ${bookstore.name}: $e");
        }
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _goToCurrentLocation() async {
    try {
      final locationData = await _locationService.getLocation();
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(locationData.latitude!, locationData.longitude!),
            15,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error getting current location: $e");
    }
  }

  void _addMarker(Bookstore bookstore, LatLng position) {
    String snippet = '${bookstore.address}';
    if (bookstore.area != null && bookstore.area! > 0) {
      snippet += '\n面積: ${bookstore.area!.toStringAsFixed(1)}㎡';
    }
    snippet += '\nToilet: ${bookstore.hasToilet ? 'Yes' : 'No'}, Cafe: ${bookstore.hasCafe ? 'Yes' : 'No'}';

    final marker = Marker(
      markerId: MarkerId(bookstore.id.toString()),
      position: position,
      infoWindow: InfoWindow(
        title: bookstore.name,
        snippet: snippet,
      ),
    );
    setState(() {
      _markers.add(marker);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('All Bookstores Map'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                _goToCurrentLocation(); // 起動時に現在地に移動
              },
              initialCameraPosition: CameraPosition(
                target: LatLng(35.681236, 139.767125), // Default to Tokyo Station
                zoom: 12,
              ),
              markers: _markers,
              myLocationEnabled: true, // 自分の位置を表示
            ),
    );
  }
}
