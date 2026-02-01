class Bookstore {
  final int? id;
  final String name;
  final String station;
  final int registers;
  final bool hasToilet;
  final bool hasCafe;

  Bookstore({
    this.id,
    required this.name,
    required this.station,
    required this.registers,
    required this.hasToilet,
    required this.hasCafe,
  });

  // データベース（Map形式）に変換する用
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'station': station,
      'registers': registers,
      'has_toilet': hasToilet ? 1 : 0, // SQLiteはboolがないので1か0で保存
      'has_cafe': hasCafe ? 1 : 0,
    };
  }
}