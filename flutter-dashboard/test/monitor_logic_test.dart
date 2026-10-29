import 'package:flutter_test/flutter_test.dart';
import 'package:iot_campus_monitor/monitor_logic.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);

  test('status online sebelum 60 detik', () {
    expect(
      readingFreshness(now.subtract(const Duration(seconds: 59)), now),
      ReadingFreshness.online,
    );
  });

  test('status stale tepat 60 detik', () {
    expect(
      readingFreshness(now.subtract(const Duration(seconds: 60)), now),
      ReadingFreshness.stale,
    );
  });

  test('status pulih dengan data baru', () {
    expect(
      readingFreshness(now.subtract(const Duration(seconds: 61)), now),
      ReadingFreshness.stale,
    );
    expect(readingFreshness(now, now), ReadingFreshness.online);
  });

  test('tren naik memakai rata-rata dua awal dan akhir', () {
    final result = temperatureTrend([20, 20, 21, 22, 22]);
    expect(result.kind, TemperatureTrendKind.naik);
    expect(result.delta, 2);
    expect(result.values, [20, 20, 21, 22, 22]);
  });

  test('tren turun', () {
    final result = temperatureTrend([22, 22, 21, 20, 20]);
    expect(result.kind, TemperatureTrendKind.turun);
    expect(result.delta, -2);
  });

  test('tren stabil saat delta tepat tolerance', () {
    final result = temperatureTrend([20, 20, 30, 20.5, 20.5]);
    expect(result.kind, TemperatureTrendKind.stabil);
    expect(result.delta, 0.5);
  });

  test('tren insufficient di bawah lima suhu', () {
    final result = temperatureTrend([20, 21, 22, 23]);
    expect(result.kind, TemperatureTrendKind.insufficient);
    expect(result.delta, isNull);
  });
}
