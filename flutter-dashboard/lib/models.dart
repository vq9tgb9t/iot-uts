class Device {
  final String id;
  final String name;
  final String location;

  Device({required this.id, required this.name, required this.location});

  factory Device.fromJson(Map<String, dynamic> j) => Device(
    id: j['device_id'].toString(),
    name: (j['name'] ?? j['device_id']).toString(),
    location: (j['location'] ?? '').toString(),
  );
}

class SensorReading {
  final int id;
  final String deviceId;
  final double? temperature;
  final double? humidity;
  final DateTime? createdAt;

  SensorReading({
    required this.id,
    required this.deviceId,
    this.temperature,
    this.humidity,
    this.createdAt,
  });

  factory SensorReading.fromJson(Map<String, dynamic> j) => SensorReading(
    id: (j['id'] as num).toInt(),
    deviceId: j['device_id'].toString(),
    temperature: (j['temperature'] as num?)?.toDouble(),
    humidity: (j['humidity'] as num?)?.toDouble(),
    createdAt: DateTime.tryParse((j['created_at'] ?? '').toString()),
  );
}
