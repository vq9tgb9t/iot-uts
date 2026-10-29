# Engineering Defense & AI Accountability

## Keputusan desain

Status offline memakai `created_at` dari penerimaan backend, bukan waktu dashboard mengambil data. ESP32/Wokwi belum memiliki sinkronisasi waktu yang dijamin, sedangkan timestamp SQLite konsisten dan tidak berubah ketika histori dibaca ulang. Alternatif timestamp perangkat ditolak karena jam perangkat dapat salah setelah boot.

Deduplikasi memakai `reading_id` stabil dan unique index SQLite. Membandingkan nilai suhu/kelembapan tidak dipakai karena dua pembacaan berbeda boleh memiliki nilai sama. Unique index dipilih dibanding pemeriksaan aplikasi saja karena tetap aman ketika dua request identik datang hampir bersamaan.

Tren memakai selisih rata-rata dua data awal dan dua data akhir dari lima data terakhir. Metode ini mudah dijelaskan dan sedikit mengurangi pengaruh satu nilai tengah. Toleransi 0,5 °C menghindari perubahan kecil diklasifikasikan sebagai naik/turun.

## Evaluasi bantuan AI

AI membantu perubahan query backend setelah penambahan `reading_id`. Pemeriksaan manual menemukan endpoint `GET /api/temperature` membentuk `TemperatureResponse` dengan `row["reading_id"]`, tetapi query awal belum memilih kolom tersebut. Query diperbaiki untuk memilih `reading_id`. Test backend lalu dijalankan memakai virtual environment yang sudah tersedia dan menghasilkan tiga test lulus.

AI juga menghasilkan logika freshness dan tren Flutter. Pemeriksaan memastikan batas offline memakai `>= 60 detik`, data diurutkan sebelum tren dihitung, serta batas toleransi `abs(delta) <= 0.5` masuk kategori Stabil. `flutter analyze` dan delapan test lulus.

## Kegagalan yang diuji

Kondisi awal: pembacaan dengan `reading_id="stable-id"` tersimpan satu kali.

Kegagalan simulasi: payload identik dikirim ulang, mewakili respons pertama hilang sehingga firmware melakukan retry.

Hasil yang diharapkan: record tidak bertambah dan backend memberi respons konsisten.

Hasil aktual: respons kedua memiliki `duplicate=true`, ID database sama, dan jumlah record untuk `stable-id` tetap satu. Test lulus.

Pengujian kegagalan jaringan firmware belum dijalankan karena PlatformIO tidak tersedia. Saat demo, hentikan backend dan pastikan serial log menunjukkan maksimal tiga hasil gagal dengan ID payload yang sama.
