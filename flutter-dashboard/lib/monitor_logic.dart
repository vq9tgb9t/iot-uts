enum ReadingFreshness { online, stale }

typedef Clock = DateTime Function();

ReadingFreshness readingFreshness(
  DateTime? createdAt,
  DateTime now, {
  Duration staleAfter = const Duration(seconds: 60),
}) {
  if (createdAt == null || now.difference(createdAt.toUtc()) >= staleAfter) {
    return ReadingFreshness.stale;
  }
  return ReadingFreshness.online;
}

enum TemperatureTrendKind { naik, turun, stabil, insufficient }

class TemperatureTrend {
  final TemperatureTrendKind kind;
  final double? delta;
  final List<double> values;

  const TemperatureTrend(this.kind, this.delta, this.values);
}

TemperatureTrend temperatureTrend(
  Iterable<double> temperatures, {
  double tolerance = 0.5,
}) {
  final values = temperatures.toList();
  if (values.length < 5) {
    return TemperatureTrend(TemperatureTrendKind.insufficient, null, values);
  }
  final latest = values.sublist(values.length - 5);
  final start = (latest[0] + latest[1]) / 2;
  final end = (latest[3] + latest[4]) / 2;
  final delta = end - start;
  final kind = delta.abs() <= tolerance
      ? TemperatureTrendKind.stabil
      : delta > 0
      ? TemperatureTrendKind.naik
      : TemperatureTrendKind.turun;
  return TemperatureTrend(kind, delta, latest);
}
