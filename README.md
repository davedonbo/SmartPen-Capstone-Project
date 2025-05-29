# 🖊️ SmartPen Capstone Project

A portable, detachable handwriting recognition system that transforms natural writing on any surface into digital text in real time. Built using embedded systems, machine learning, and Bluetooth-enabled mobile integration.

## 📜 Project Overview

This project aims to solve the limitations of existing handwriting recognition systems by introducing a smart pen attachment that leverages inertial sensors (IMU) and a lightweight on-device machine learning model. Unlike stylus-based or surface-constrained systems, this smart pen works with standard pens and supports writing on any surface—including in mid-air.

### 🎯 Key Features
- Real-time handwriting recognition
- Supports uppercase letters
- Wireless transmission of recognized characters to a mobile app
- Compatible with any standard pen
- On-device inference using quantized CNN model

---

## 🗂️ Repository Structure

SmartPen-Capstone-Project/
│
├── Embedded Code/ # Firmware for microcontroller (Arduino)
├── Machine Learning/ # Notebook
├── Mobile/ # Flutter mobile app source code
├── .gitignore
└── README.md # You're here!

---

## ⚙️ Technologies Used

| Component        | Technology                          |
|------------------|-------------------------------------|
| Microcontroller  | STM32WB55CG / Arduino Nano 33 BLE   |
| IMU Sensor       | LSM6DSL (6-axis) / LSM9DS1 (9-axis  |
| Model Framework  | TensorFlow Lite (Quantized CNN)     |
| App Framework    | Flutter (Dart)                      |
| Wireless Comm    | Bluetooth Low Energy (BLE 5.0)      |

---

## 🚀 Getting Started

### Prerequisites
- [Arduino IDE](https://www.arduino.cc/en/software)
- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- Python 3.8+, TensorFlow 2.8, and required packages for model training

### 1️⃣ Embedded Code

```bash
cd Embedded\ Code/
# Open in STM32CubeIDE or Arduino IDE
# Flash the board with appropriate binary
2️⃣ Mobile App
cd Mobile/
flutter pub get
flutter run
Make sure Bluetooth is enabled and location permissions are granted.

3️⃣ Machine Learning
cd Machine\ Learning/
# Train or retrain model using Jupyter notebooks
# Deploy final quantized model (model.tflite) to firmware
📱 How It Works
The IMU captures pen motion data.

Data is fed into a CNN model running on the microcontroller.

Recognized character is sent over BLE to the mobile app.

The app displays the transcribed character in real time.


🧪 Testing & Performance
Achieved ~90% accuracy on trained character set

Maintains 85-90% accuracy even in mid-air writing

Tested on paper, whiteboard, cardboard, etc.

End-to-end latency: ~100ms

📌 Authors
Dave Leori Donbo

Daniel Tunyinko
Ashesi University Capstone Project – 2025

🙌 Acknowledgements
Dr. Nathan Amanquah – Supervisor

Ashesi University – Department of Engineering

TensorFlow, STMicroelectronics, Arduino, Flutter
