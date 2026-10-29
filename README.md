# IoT Reliability & Intelligent Monitoring

Proyek UTS monitoring suhu dan kelembapan dengan ESP32, DHT22, Wokwi, FastAPI, SQLite, dan Flutter.

## Struktur

- `backend-esp32/`: firmware PlatformIO, simulasi Wokwi, FastAPI, test backend, dan laporan UTS.
- `flutter-dashboard/`: dashboard Flutter, status offline 60 detik, analisis tren, dan test.

## Backend

```bash
cd backend-esp32
python -m venv .venv
.venv/bin/pip install -r requirements.txt
API_KEY="replace-with-demo-key" .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
```

## Firmware Wokwi

Samakan `API_KEY` di `backend-esp32/platformio.ini` dengan environment backend, lalu:

```bash
cd backend-esp32
pio run
```

Jalankan Wokwi memakai `wokwi.toml`.

## Flutter

```bash
cd flutter-dashboard
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Test

```bash
cd backend-esp32
.venv/bin/python -m unittest -v test_main.py

cd ../flutter-dashboard
flutter analyze
flutter test
```

Dokumentasi dan laporan tersedia di `backend-esp32/docs/uts/`.
