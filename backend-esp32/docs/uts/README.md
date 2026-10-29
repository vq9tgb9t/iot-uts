# Laporan UTS IoT Reliability & Intelligent Monitoring

## Basis proyek

Proyek terpilih:

- `sensor suhu`: ESP32, DHT22, Wokwi, FastAPI, SQLite.
- `iot_campus_monitor`: dashboard Flutter yang sudah memakai endpoint backend tersebut.

Kombinasi ini dipilih karena sudah memiliki alur ESP32 → FastAPI → SQLite → Flutter. Kandidat `led-esp32-v1` tidak memiliki Flutter terintegrasi dan hanya menyimpan suhu; kandidat `arduino` tidak memakai DHT22/FastAPI/Flutter.

## Implementasi

### Offline Detection & Recovery

Flutter menentukan status dari `created_at` pembacaan terbaru. Data berusia kurang dari 60 detik berstatus `Online • Updated`; data tanpa timestamp atau berusia minimal 60 detik berstatus `Offline • Stale`. Timer UI mengevaluasi ulang status setiap detik. Refresh histori tidak mengubah timestamp. Error API ditampilkan terpisah dan tidak langsung dijadikan bukti perangkat offline.

Kode: `iot_campus_monitor/lib/monitor_logic.dart`, `iot_campus_monitor/lib/main.dart`.

### Sensor Data Validation

FastAPI mewajibkan `reading_id`, `device_id`, `temperature_c`, dan `humidity`. Suhu valid 20–30 °C inklusif; kelembapan valid 0–100% inklusif. Pydantic menolak tipe/format salah serta NaN/Infinity sebelum insert sehingga data invalid tidak masuk histori.

Kode: `sensor suhu/main.py`.

### Smart Retry & Duplicate Prevention

Firmware membuat satu `reading_id` per pembacaan dan memakai ID sama pada seluruh retry. Maksimal tiga percobaan memakai jeda 500 ms lalu 1000 ms. Retry hanya dilakukan untuk gangguan transport, HTTP 408, 429, atau 5xx; respons 4xx permanen tidak diulang.

Backend menambah kolom `reading_id` secara additive. Data lama diberi ID `legacy-<id>`. Unique index SQLite menegakkan deduplikasi termasuk request bersamaan. Request ulang mengembalikan record awal dengan `duplicate: true` dan tidak menambah histori.

Kode: `sensor suhu/src/main.cpp`, `sensor suhu/main.py`.

### Temperature Trend Analysis

Flutter memakai lima suhu valid terakhir dalam urutan timestamp. Rumus:

- `awal = rata-rata data ke-1 dan ke-2`
- `akhir = rata-rata data ke-4 dan ke-5`
- `delta = akhir - awal`
- `|delta| <= 0,5 °C`: Stabil
- `delta > 0,5 °C`: Naik
- `delta < -0,5 °C`: Turun

Dashboard menampilkan kategori, delta, dan lima nilai. Jika kurang dari lima data, tampil `Data belum cukup`.

Kode: `iot_campus_monitor/lib/monitor_logic.dart`, `iot_campus_monitor/lib/main.dart`.

## Hasil pengujian

| ID | Skenario | Hasil aktual | Status | Bukti |
|---|---|---|---|---|
| B-01 | Batas suhu 20 dan 30; kelembapan 0 | Diterima model | PASS | `test_main.py` |
| B-02 | Suhu di luar rentang, kelembapan -1/101, NaN | Ditolak model | PASS | `test_main.py` |
| B-03 | Kirim ID sama dua kali | Satu record; kedua respons `duplicate=true` | PASS | `test_main.py` |
| B-04 | Migrasi skema lama | ID legacy dan unique index terbentuk | PASS | `test_main.py` |
| F-01 | Data umur 59 detik | Online | PASS | `test/monitor_logic_test.dart` |
| F-02 | Data umur tepat 60 detik | Stale | PASS | `test/monitor_logic_test.dart` |
| F-03 | Data stale lalu data baru | Pulih Online | PASS | `test/monitor_logic_test.dart` |
| F-04 | Tren naik, turun, stabil, data kurang | Semua klasifikasi sesuai rumus | PASS | `test/monitor_logic_test.dart` |
| F-05 | Dashboard memakai API mock | Nilai dan komponen dashboard tampil | PASS | `test/widget_test.dart` |
| E-01 | Build firmware dan retry pada jaringan gagal | Tool `pio` tidak tersedia di PATH | NOT TESTED | Perlu Wokwi/PlatformIO |
| I-01 | Backend + firmware + Flutter grafis end-to-end | Lingkungan grafis/perangkat tidak dijalankan | NOT TESTED | Perlu screenshot manual |

Perintah aktual dan hasil:

```text
/home/vq/Desktop/matkul-iot/led-esp32-v1/env/bin/python -m unittest -v test_main.py
Ran 3 tests ... OK

flutter analyze
No issues found!

flutter test
00:01 +8: All tests passed!
```

## Cara menjalankan

Backend:

```bash
cd "/home/vq/Desktop/matkul-iot/sensor suhu"
python -m venv .venv
.venv/bin/pip install -r requirements.txt
API_KEY="ganti-dengan-key-demo" .venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
```

Flutter desktop lokal:

```bash
cd "/home/vq/Desktop/matkul-iot/iot_campus_monitor"
flutter pub get
flutter run
```

Flutter emulator/perangkat lain:

```bash
flutter run --dart-define=API_BASE_URL=http://IP_BACKEND:8000
```

Test:

```bash
cd "/home/vq/Desktop/matkul-iot/sensor suhu"
.venv/bin/python -m unittest -v test_main.py

cd "/home/vq/Desktop/matkul-iot/iot_campus_monitor"
flutter analyze
flutter test
```

Firmware/Wokwi:

```bash
cd "/home/vq/Desktop/matkul-iot/sensor suhu"
pio run
```

Sesuaikan `SERVER_URL` dan `API_KEY` melalui build flags lokal sebelum demo. Jangan memasukkan key produksi ke laporan.

## Bukti manual yang harus diambil

1. Screenshot dashboard saat Online, tepat setelah data baru.
2. Screenshot dashboard saat Offline setelah pengiriman berhenti minimal 60 detik.
3. Screenshot dashboard kembali Online setelah pengiriman dilanjutkan.
4. Screenshot kategori tren dengan minimal lima data.
5. Log serial tiga percobaan saat backend sengaja dihentikan.
6. Respons HTTP data valid, invalid 422, dan duplikat `duplicate: true`.
7. Query jumlah record sebelum/sesudah request duplikat.

Jangan nyatakan perangkat fisik berhasil bila bukti hanya berasal dari Wokwi.

## Keterbatasan

- Build firmware dan simulasi Wokwi belum diverifikasi karena `pio` tidak tersedia di PATH.
- UI grafis dan integrasi end-to-end belum dijalankan; screenshot belum tersedia.
- Pending queue lintas reboot tidak dibuat. Retry hanya mempertahankan pembacaan selama fungsi pengiriman aktif.
- Timestamp memakai waktu penerimaan SQLite UTC, bukan waktu sensor; pilihan ini menjaga status konsisten saat jam perangkat belum tersinkronisasi.
