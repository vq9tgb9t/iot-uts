import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iot_campus_monitor/api_service.dart';
import 'package:iot_campus_monitor/main.dart';

void main() {
  testWidgets('menampilkan dashboard dan data perangkat', (tester) async {
    final client = MockClient((request) async {
      if (request.url.path == '/api/device') {
        return http.Response(
          jsonEncode([
            {
              'device_id': 'ESP32_DHT22',
              'name': 'Sensor DHT22',
              'location': 'Lab IoT',
            },
          ]),
          200,
        );
      }
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'device_id': 'ESP32_DHT22',
            'temperature': 25.5,
            'humidity': 60.0,
            'created_at': '2026-10-23T12:00:00Z',
          },
        ]),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          api: ApiService(client: client),
          startAutoRefresh: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Monitor Suhu'), findsOneWidget);
    expect(find.text('Sensor DHT22'), findsWidgets);
    expect(find.text('25.5 °C'), findsOneWidget);
    expect(find.text('60.0%'), findsOneWidget);
    expect(find.text('Riwayat suhu'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
