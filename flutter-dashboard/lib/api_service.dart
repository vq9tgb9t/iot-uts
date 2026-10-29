import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiService {
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  final http.Client client;
  final String baseUrl;

  ApiService({http.Client? client, this.baseUrl = defaultBaseUrl})
    : client = client ?? http.Client();

  Future<List<dynamic>> _getList(String path) async {
    final response = await client
        .get(Uri.parse('$baseUrl$path'))
        .timeout(const Duration(seconds: 8));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $path');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      throw const FormatException('Expected JSON list');
    }

    return decoded;
  }

  Future<List<Device>> getDevices() async =>
      (await _getList('/api/device'))
          .map((e) => Device.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<List<SensorReading>> getSensors({
    String? deviceId,
    int limit = 30,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (deviceId != null) query['device_id'] = deviceId;
    final uri = Uri(path: '/api/sensor', queryParameters: query);

    return (await _getList(uri.toString()))
        .map((e) => SensorReading.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
