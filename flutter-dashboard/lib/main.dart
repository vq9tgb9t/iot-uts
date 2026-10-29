import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'api_service.dart';
import 'models.dart';
import 'monitor_logic.dart';

void main() => runApp(const IoTApp());

class IoTApp extends StatelessWidget {
  const IoTApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Monitor Suhu',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff2457a6),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.white,
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Color(0xffd5d9e0)),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
    home: const DashboardPage(),
  );
}

class DashboardPage extends StatefulWidget {
  final ApiService? api;
  final bool startAutoRefresh;
  final Clock clock;

  const DashboardPage({
    super.key,
    this.api,
    this.startAutoRefresh = true,
    this.clock = DateTime.now,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  late final ApiService api;
  Timer? refreshTimer;
  Timer? statusTimer;
  bool loading = false;
  bool autoRefresh = true;
  bool appActive = true;
  String? error;
  String? selectedDeviceId;
  List<Device> devices = [];
  List<SensorReading> readings = [];
  final Map<String, bool> hotState = {};

  @override
  void initState() {
    super.initState();
    api = widget.api ?? ApiService();
    autoRefresh = widget.startAutoRefresh;
    WidgetsBinding.instance.addObserver(this);
    _configureTimer();
    statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    refresh();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    appActive = state == AppLifecycleState.resumed;
    _configureTimer();
    if (appActive && autoRefresh) refresh();
  }

  void _configureTimer() {
    refreshTimer?.cancel();
    if (autoRefresh && appActive) {
      refreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => refresh(),
      );
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      var currentDevices = devices;
      if (currentDevices.isEmpty) currentDevices = await api.getDevices();
      if (!mounted) return;

      var currentId = selectedDeviceId;
      if (currentId == null ||
          !currentDevices.any((device) => device.id == currentId)) {
        currentId = currentDevices.isEmpty ? null : currentDevices.first.id;
      }

      final currentReadings = currentId == null
          ? <SensorReading>[]
          : await api.getSensors(deviceId: currentId, limit: 30);
      if (!mounted) return;

      currentReadings.sort(_compareReadings);
      setState(() {
        devices = currentDevices;
        selectedDeviceId = currentId;
        readings = currentReadings;
      });
      _checkHeatAlert();
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = 'Pembaruan gagal. Periksa koneksi backend.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  int _compareReadings(SensorReading a, SensorReading b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime != null && bTime != null) {
      final result = aTime.compareTo(bTime);
      if (result != 0) return result;
    }
    return a.id.compareTo(b.id);
  }

  SensorReading? get latest => readings.isEmpty ? null : readings.last;

  Device? get selectedDevice {
    for (final device in devices) {
      if (device.id == selectedDeviceId) return device;
    }
    return null;
  }

  void _checkHeatAlert() {
    final current = latest;
    final deviceId = selectedDeviceId;
    if (current == null || deviceId == null || current.temperature == null) {
      return;
    }

    final isHot = current.temperature! > 30;
    final wasHot = hotState[deviceId] ?? false;
    hotState[deviceId] = isHot;
    if (!isHot || wasHot) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Suhu tinggi'),
          content: Text(
            '${selectedDevice?.name ?? deviceId}: '
            '${current.temperature!.toStringAsFixed(1)} °C',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _selectDevice(String? deviceId) async {
    if (deviceId == null || deviceId == selectedDeviceId) return;
    setState(() {
      selectedDeviceId = deviceId;
      readings = [];
    });
    await refresh();
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '-';
    final time = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final current = latest;
    final freshness = readingFreshness(current?.createdAt, widget.clock());
    final trend = temperatureTrend(
      readings
          .where((reading) => reading.temperature != null)
          .map((reading) => reading.temperature!),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor Suhu'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              DropdownButtonFormField<String>(
                key: const Key('deviceDropdown'),
                initialValue: selectedDeviceId,
                decoration: const InputDecoration(
                  labelText: 'Perangkat',
                  border: OutlineInputBorder(),
                ),
                items: devices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device.id,
                        child: Text(device.name),
                      ),
                    )
                    .toList(),
                onChanged: loading ? null : _selectDevice,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: loading ? null : refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  const Spacer(),
                  const Text('Otomatis'),
                  Switch(
                    value: autoRefresh,
                    onChanged: (value) {
                      setState(() => autoRefresh = value);
                      _configureTimer();
                    },
                  ),
                ],
              ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _ReadingSummary(
                device: selectedDevice,
                reading: current,
                time: _formatTime(current?.createdAt),
                freshness: freshness,
              ),
              const SizedBox(height: 12),
              _TrendSummary(trend: trend),
              const SizedBox(height: 20),
              Text(
                'Riwayat suhu',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: _TemperatureChart(readings: readings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingSummary extends StatelessWidget {
  final Device? device;
  final SensorReading? reading;
  final String time;
  final ReadingFreshness freshness;

  const _ReadingSummary({
    required this.device,
    required this.reading,
    required this.time,
    required this.freshness,
  });

  @override
  Widget build(BuildContext context) {
    final temperature = reading?.temperature;
    final humidity = reading?.humidity;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device?.name ?? 'Belum ada perangkat',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if ((device?.location ?? '').isNotEmpty) Text(device!.location),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Value(
                    label: 'Suhu',
                    value: temperature == null
                        ? '-'
                        : '${temperature.toStringAsFixed(1)} °C',
                  ),
                ),
                Expanded(
                  child: _Value(
                    label: 'Kelembapan',
                    value: humidity == null
                        ? '-'
                        : '${humidity.toStringAsFixed(1)}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              freshness == ReadingFreshness.online
                  ? 'Online • Updated'
                  : 'Offline • Stale',
              key: const Key('freshnessStatus'),
              style: TextStyle(
                color: freshness == ReadingFreshness.online
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('Pembaruan terakhir: $time'),
          ],
        ),
      ),
    );
  }
}

class _TrendSummary extends StatelessWidget {
  final TemperatureTrend trend;

  const _TrendSummary({required this.trend});

  @override
  Widget build(BuildContext context) {
    final label = switch (trend.kind) {
      TemperatureTrendKind.naik => 'Naik',
      TemperatureTrendKind.turun => 'Turun',
      TemperatureTrendKind.stabil => 'Stabil',
      TemperatureTrendKind.insufficient => 'Data belum cukup',
    };
    final values = trend.values
        .map((value) => value.toStringAsFixed(1))
        .join(', ');
    final delta = trend.delta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tren suhu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(label, key: const Key('trendCategory')),
            Text(
              delta == null
                  ? 'Delta: -'
                  : 'Delta: ${delta.toStringAsFixed(1)} °C',
            ),
            Text('5 nilai: ${values.isEmpty ? '-' : values}'),
          ],
        ),
      ),
    );
  }
}

class _Value extends StatelessWidget {
  final String label;
  final String value;

  const _Value({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
    ],
  );
}

class _TemperatureChart extends StatelessWidget {
  final List<SensorReading> readings;

  const _TemperatureChart({required this.readings});

  @override
  Widget build(BuildContext context) {
    final values = readings
        .where((reading) => reading.temperature != null)
        .toList();
    if (values.isEmpty) return const Center(child: Text('Belum ada data'));

    final spots = [
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index].temperature!),
    ];
    final temperatures = values.map((item) => item.temperature!).toList();
    final minimum = temperatures.reduce((a, b) => a < b ? a : b);
    final maximum = temperatures.reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: minimum - 2,
        maxY: maximum + 2,
        borderData: FlBorderData(show: true),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: values.length > 6
                  ? (values.length / 5).ceilToDouble()
                  : 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= values.length) {
                  return const SizedBox.shrink();
                }
                final time = values[index].createdAt?.toLocal();
                if (time == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${time.hour.toString().padLeft(2, '0')}:'
                    '${time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 42),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)} °C',
                    const TextStyle(color: Colors.white),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Theme.of(context).colorScheme.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }
}
