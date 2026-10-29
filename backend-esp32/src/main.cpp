#include <WiFi.h>
#include <HTTPClient.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "DHT.h"

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

#define DHTPIN 15
#define DHTTYPE DHT22
#define LED_PIN 2
const float THRESHOLD_TEMP = 30.0;
DHT dht(DHTPIN, DHTTYPE);

const char* ssid = "Wokwi-GUEST";
const char* password = "";

#ifndef SERVER_URL
#define SERVER_URL "http://10.10.6.143:8000/api/temperature"
#endif
#ifndef API_KEY
#define API_KEY ""
#endif
const char* serverUrl = SERVER_URL;
const char* apiKey = API_KEY;

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  Wire.begin(21, 22);
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  dht.begin();

  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected!");
}

void loop() {
  delay(3000);

  float temp = dht.readTemperature();
  float hum = dht.readHumidity();

  if (isnan(temp) || isnan(hum)) return;

  Serial.print("Suhu: ");
  Serial.print(temp, 2);
  Serial.print(" C, Kelembapan: ");
  Serial.print(hum, 2);
  Serial.println(" %");

  // Logika kontrol LED suhu panas
  if (temp > THRESHOLD_TEMP) {
    digitalWrite(LED_PIN, HIGH);
  } else {
    digitalWrite(LED_PIN, LOW);
  }

  // Update tampilan Layar OLED
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("MONITORING SUHU IOT");
  display.drawLine(0, 10, 128, 10, SSD1306_WHITE);

  display.setCursor(0, 20);
  display.print("Suhu  : ");
  display.print(temp, 1);
  display.println(" C");

  display.setCursor(0, 36);
  display.print("Lembap: ");
  display.print(hum, 1);
  display.println(" %");

  display.setCursor(0, 52);
  display.print("Status: ");
  display.println(temp > THRESHOLD_TEMP ? "PANAS [ON]" : "NORMAL [OFF]");
  display.display();

  String readingId = String((uint32_t)(ESP.getEfuseMac() >> 32), HEX) + "-" +
                     String((uint32_t)ESP.getEfuseMac(), HEX) + "-" +
                     String(millis(), HEX) + "-" + String(esp_random(), HEX);
  String postData = "{\"reading_id\":\"" + readingId +
                    "\",\"device_id\":\"ESP32_DHT22\",\"temperature_c\":" +
                    String(temp, 2) + ",\"humidity\":" + String(hum, 2) + "}";

  Serial.print("Reading ID: ");
  Serial.println(readingId);

  for (int attempt = 0; attempt < 3; attempt++) {
    Serial.print("Percobaan ");
    Serial.print(attempt + 1);
    Serial.println("/3");
    if (WiFi.status() != WL_CONNECTED) {
      WiFi.disconnect();
      WiFi.begin(ssid, password);
      unsigned long started = millis();
      while (WiFi.status() != WL_CONNECTED && millis() - started < 5000) delay(100);
    }

    int httpResponseCode = -1;
    if (WiFi.status() == WL_CONNECTED) {
      HTTPClient http;
      http.setConnectTimeout(5000);
      http.setTimeout(5000);
      http.begin(serverUrl);
      http.addHeader("Content-Type", "application/json");
      http.addHeader("X-API-Key", apiKey);
      httpResponseCode = http.POST(postData);
      if (httpResponseCode > 0) {
        Serial.print("Respons body: ");
        Serial.println(http.getString());
      }
      http.end();
    }

    Serial.print("Respons HTTP: ");
    Serial.println(httpResponseCode);
    bool retryable = httpResponseCode <= 0 || httpResponseCode >= 500 ||
                     httpResponseCode == 408 || httpResponseCode == 429;
    if (!retryable || attempt == 2) break;
    delay(500 * (1 << attempt));
  }
}