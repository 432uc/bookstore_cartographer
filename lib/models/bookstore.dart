class Bookstore {
  final int? id;
  final String name;
  final String station;
  final int registers;
  final bool hasToilet;
  final bool hasCafe;
  final String address;
  final String? pathData; // JSON serialized list of points
  final double? area;

  Bookstore({
    this.id,
    required this.name,
    required this.station,
    required this.registers,
    required this.hasToilet,
    required this.hasCafe,
    required this.address,
    this.pathData,
    this.area,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'station': station,
      'registers': registers,
      'has_toilet': hasToilet ? 1 : 0,
      'has_cafe': hasCafe ? 1 : 0,
      'address': address,
      'path_data': pathData,
      'area': area,
    };
  }
}
