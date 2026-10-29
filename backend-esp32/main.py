import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator

DATABASE_PATH = Path(os.getenv("DATABASE_PATH", Path(__file__).with_name("iot.sqlite")))
API_KEY = os.getenv("API_KEY")

app = FastAPI(title="IoT Temperature API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class TemperatureCreate(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)

    reading_id: str = Field(min_length=1, max_length=100)
    device_id: str = Field(min_length=1, max_length=50)
    temperature_c: float = Field(ge=20, le=30)
    humidity: float = Field(ge=0, le=100)

    @field_validator("reading_id", "device_id")
    @classmethod
    def validate_identifier(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("ID tidak boleh kosong")
        return value


class TemperatureResponse(BaseModel):
    id: int
    reading_id: str
    device_id: str
    temperature_c: float
    humidity: float
    timestamp: datetime
    duplicate: bool = False


class DeviceResponse(BaseModel):
    device_id: str
    name: str
    location: str


class SensorResponse(BaseModel):
    id: int
    device_id: str
    temperature: float
    humidity: float | None
    created_at: datetime


@contextmanager
def database():
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
    finally:
        connection.close()


def initialize_database() -> None:
    with database() as connection:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS devices (
                device_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                location TEXT NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS sensor_readings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                temperature REAL NOT NULL,
                humidity REAL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (device_id) REFERENCES devices(device_id)
            )
            """
        )
        columns = {
            row["name"]
            for row in connection.execute("PRAGMA table_info(sensor_readings)").fetchall()
        }
        if "reading_id" not in columns:
            connection.execute("ALTER TABLE sensor_readings ADD COLUMN reading_id TEXT")
        connection.execute(
            "UPDATE sensor_readings SET reading_id = 'legacy-' || id WHERE reading_id IS NULL OR reading_id = ''"
        )
        connection.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS ux_sensor_readings_reading_id ON sensor_readings(reading_id)"
        )
        connection.execute(
            "INSERT OR IGNORE INTO devices (device_id, name, location) VALUES (?, ?, ?)",
            ("ESP32_DHT22", "Sensor DHT22", "Laboratorium IoT"),
        )
        connection.commit()


def verify_api_key(x_api_key: str | None) -> None:
    if not API_KEY:
        raise HTTPException(status_code=500, detail="API key belum dikonfigurasi")
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace(" ", "T")).replace(tzinfo=timezone.utc)


initialize_database()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/api/temperature", response_model=TemperatureResponse, status_code=201)
def create_temperature(
    data: TemperatureCreate,
    x_api_key: Annotated[str | None, Header()] = None,
):
    verify_api_key(x_api_key)
    with database() as connection:
        connection.execute(
            "INSERT OR IGNORE INTO devices (device_id, name, location) VALUES (?, ?, ?)",
            (data.device_id, data.device_id, ""),
        )
        try:
            cursor = connection.execute(
                "INSERT INTO sensor_readings (reading_id, device_id, temperature, humidity) VALUES (?, ?, ?, ?)",
                (data.reading_id, data.device_id, data.temperature_c, data.humidity),
            )
            connection.commit()
            row = connection.execute(
                "SELECT id, reading_id, device_id, temperature, humidity, created_at FROM sensor_readings WHERE id = ?",
                (cursor.lastrowid,),
            ).fetchone()
            duplicate = False
        except sqlite3.IntegrityError:
            connection.rollback()
            row = connection.execute(
                "SELECT id, reading_id, device_id, temperature, humidity, created_at FROM sensor_readings WHERE reading_id = ?",
                (data.reading_id,),
            ).fetchone()
            if row is None:
                raise
            duplicate = True

    return TemperatureResponse(
        id=row["id"],
        reading_id=row["reading_id"],
        device_id=row["device_id"],
        temperature_c=row["temperature"],
        humidity=row["humidity"],
        timestamp=parse_timestamp(row["created_at"]),
        duplicate=duplicate,
    )


@app.get("/api/temperature", response_model=list[TemperatureResponse])
def get_temperatures(limit: int = Query(default=60, ge=1, le=500)):
    with database() as connection:
        rows = connection.execute(
            "SELECT id, reading_id, device_id, temperature, humidity, created_at FROM sensor_readings ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()

    return [
        TemperatureResponse(
            id=row["id"],
            reading_id=row["reading_id"],
            device_id=row["device_id"],
            temperature_c=row["temperature"],
            humidity=row["humidity"],
            timestamp=parse_timestamp(row["created_at"]),
        )
        for row in rows
    ]


@app.get("/api/device", response_model=list[DeviceResponse])
def get_devices():
    with database() as connection:
        rows = connection.execute(
            "SELECT device_id, name, location FROM devices ORDER BY device_id"
        ).fetchall()

    return [DeviceResponse(**dict(row)) for row in rows]


@app.get("/api/sensor", response_model=list[SensorResponse])
def get_sensors(
    limit: int = Query(default=100, ge=1, le=500),
    device_id: str | None = None,
):
    with database() as connection:
        if device_id:
            rows = connection.execute(
                "SELECT id, device_id, temperature, humidity, created_at FROM sensor_readings WHERE device_id = ? ORDER BY id DESC LIMIT ?",
                (device_id, limit),
            ).fetchall()
        else:
            rows = connection.execute(
            "SELECT id, reading_id, device_id, temperature, humidity, created_at FROM sensor_readings ORDER BY id DESC LIMIT ?",
                (limit,),
            ).fetchall()

    return [
        SensorResponse(
            id=row["id"],
            device_id=row["device_id"],
            temperature=row["temperature"],
            humidity=row["humidity"],
            created_at=parse_timestamp(row["created_at"]),
        )
        for row in rows
    ]
