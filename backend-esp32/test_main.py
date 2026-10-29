import math
import sqlite3
import tempfile
import unittest
from pathlib import Path

import main
from pydantic import ValidationError


class TemperatureTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        main.DATABASE_PATH = Path(self.tempdir.name) / "test.sqlite"
        main.API_KEY = "test-key"
        main.initialize_database()

    def tearDown(self):
        self.tempdir.cleanup()

    def test_duplicate_reading_is_idempotent(self):
        data = main.TemperatureCreate(
            reading_id="stable-id",
            device_id="device",
            temperature_c=20,
            humidity=100,
        )
        first = main.create_temperature(data, "test-key")
        second = main.create_temperature(data, "test-key")
        self.assertFalse(first.duplicate)
        self.assertTrue(second.duplicate)
        self.assertEqual(first.id, second.id)
        with main.database() as connection:
            count = connection.execute(
                "SELECT COUNT(*) FROM sensor_readings WHERE reading_id = ?",
                (data.reading_id,),
            ).fetchone()[0]
        self.assertEqual(count, 1)

    def test_validation_boundaries_and_nonfinite(self):
        for temperature in (20, 30):
            main.TemperatureCreate(
                reading_id=str(temperature),
                device_id="device",
                temperature_c=temperature,
                humidity=0,
            )
        for field, value in (("temperature_c", 19.99), ("temperature_c", 30.01), ("humidity", -1), ("humidity", 101), ("humidity", math.nan)):
            payload = dict(reading_id="id", device_id="device", temperature_c=25, humidity=50)
            payload[field] = value
            with self.assertRaises(ValidationError):
                main.TemperatureCreate(**payload)

    def test_legacy_migration(self):
        legacy = Path(self.tempdir.name) / "legacy.sqlite"
        connection = sqlite3.connect(legacy)
        connection.executescript(
            "CREATE TABLE devices (device_id TEXT PRIMARY KEY, name TEXT NOT NULL, location TEXT NOT NULL);"
            "CREATE TABLE sensor_readings (id INTEGER PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, temperature REAL NOT NULL, humidity REAL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);"
            "INSERT INTO devices VALUES ('old', 'old', '');"
            "INSERT INTO sensor_readings (device_id, temperature, humidity) VALUES ('old', 25, 50);"
        )
        connection.commit()
        connection.close()
        main.DATABASE_PATH = legacy
        main.initialize_database()
        with main.database() as connection:
            row = connection.execute("SELECT reading_id FROM sensor_readings").fetchone()
            indexes = connection.execute("PRAGMA index_list(sensor_readings)").fetchall()
        self.assertEqual(row["reading_id"], "legacy-1")
        self.assertTrue(any(index["name"] == "ux_sensor_readings_reading_id" and index["unique"] for index in indexes))


if __name__ == "__main__":
    unittest.main()
