class Bookstore {
  final int? id;
  final String name;
  final String station;
  final int registers;
  final bool hasToilet;
  final bool hasCafe;
  final String address;

  Bookstore({
    this.id,
    required this.name,
    required this.station,
    required this.registers,
    required this.hasToilet,
    required this.hasCafe,
    required this.address,
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
    };
  }
}
