import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'database_helper.dart';
import 'models/bookstore.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookstores();
  }

  Future<void> _loadBookstores() async {
    final bookstores = await DatabaseHelper.instance.queryAllStores();
    for (final bookstore in bookstores) {
      if (bookstore.address.isNotEmpty) {
        try {
          final locations = await locationFromAddress(bookstore.address);
          if (locations.isNotEmpty) {
            final location = locations.first;
            _addMarker(bookstore, LatLng(location.latitude, location.longitude));
          }
        } catch (e) {
          // Handle geocoding error
        }
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  void _addMarker(Bookstore bookstore, LatLng position) {
    final marker = Marker(
      markerId: MarkerId(bookstore.id.toString()),
      position: position,
      infoWindow: InfoWindow(
        title: bookstore.name,
        snippet: '${bookstore.address}\nToilet: ${bookstore.hasToilet ? 'Yes' : 'No'}, Cafe: ${bookstore.hasCafe ? 'Yes' : 'No'}',
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
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: CameraPosition(
                target: LatLng(35.681236, 139.767125), // Default to Tokyo Station
                zoom: 12,
              ),
              markers: _markers,
            ),
    );
  }
}
