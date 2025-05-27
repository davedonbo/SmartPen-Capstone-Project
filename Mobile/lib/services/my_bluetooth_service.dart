import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
// import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';
import 'package:permission_handler/permission_handler.dart';

enum PenConnection { scanning, connected, disconnected }

class MyBluetoothService {
  MyBluetoothService._internal();
  static final MyBluetoothService _singleton = MyBluetoothService._internal();
  factory MyBluetoothService() => _singleton;

  // ─── UUIDs – replace with your own if they differ ────────────────────────
  static final Guid _serviceUuid =
  Guid('19B10000-E8F2-537E-4F6C-D104768A1214');
  static final Guid _dataUuid =
  Guid('19B10001-E8F2-537E-4F6C-D104768A1214');
  static final Guid _commandUuid =
  Guid('19B10002-E8F2-537E-4F6C-D104768A1214');

  // ─── State ----------------------------------------------------------------
  BluetoothDevice?                  _device;
  BluetoothCharacteristic?          _dataChar;
  BluetoothCharacteristic?          _cmdChar;
  StreamSubscription<List<int>>?    _dataSub;
  StreamSubscription<List<int>>? _infoSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _connCtrl = StreamController<PenConnection>.broadcast();
  Stream<PenConnection> get connectionStream => _connCtrl.stream;
  bool get isConnected => _device?.isConnected ?? false;

  // Internal helpers
  bool _initialising = false;
  bool _connecting   = false;
  final _rxBuffer    = StringBuffer();

  // ─── Public API -----------------------------------------------------------
  Future<void> initialize() async {
    if (_initialising) return;
    _initialising = true;

    await _ensurePermissions();
    _connCtrl.add(PenConnection.scanning);

    if (await FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState.firstWhere((s) => s == BluetoothAdapterState.on);
    }



    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      withServices: [_serviceUuid],
    );

    FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.serviceUuids.contains(_serviceUuid) ||
            r.device.name == 'SmartPen') {
          FlutterBluePlus.stopScan();
          _connect(r.device);
        }
      }
    });

    // If we still aren’t connected after the scan, downgrade the state.
    Future.delayed(const Duration(seconds: 16), () {
      if (!isConnected) _connCtrl.add(PenConnection.disconnected);
    });

    _initialising = false;
  }

  Future<void> connect() => initialize();
  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanUp();
  }

  // Live-capture (single-character streaming) -------------------------------
  Future<void> startLiveCapture(void Function(String ch) onChar) async {
    if (_dataChar == null) return;   // not yet discovered

    await _dataSub?.cancel();        // drop a previous listener if any
    await _ensureNotifying(_dataChar!);
    _rxBuffer.clear();

    _dataSub = _dataChar!.onValueReceived.listen((bytes) {
      _rxBuffer.write(utf8.decode(bytes));

      while (_rxBuffer.toString().contains('\n')) {
        final idx = _rxBuffer.toString().indexOf('\n');
        final line = _rxBuffer.toString().substring(0, idx).trim();
        _rxBuffer.clear();
        _rxBuffer.write(
            idx + 1 < line.length ? line.substring(idx + 1) : '');
        // print("information: ${line}");

        if (line.startsWith('PRED:') && line.length >= 6) {
          if(line.contains('?')) continue;
          onChar(line.substring(5, 6)); // first char after “PRED:”
        }

      }
    });

    _device?.cancelWhenDisconnected(_dataSub!);
    await _sendCommand(1); // start predictions
  }

  Future<void> stopLiveCapture() async {
    await _dataSub?.cancel();
    _dataSub = null;
    if (isConnected) {
      await _sendCommand(0); // stop predictions
      await _dataChar?.setNotifyValue(false);
    }
  }

  StreamSubscription<List<int>>? listenForInfoSleep(VoidCallback onSleep) {
    // ensure notifications are on
    if (_dataChar == null) {
      return null;
    }
    _ensureNotifying(_dataChar!);

    // attach an *independent* listener (doesn’t touch _dataSub)
    _infoSub = _dataChar!.onValueReceived.listen((bytes) {
      final line = utf8.decode(bytes, allowMalformed: true);
      if (line.contains('INFO:SLEEP')) {
        onSleep();
      }
    });
    return _infoSub!;
  }

  // Bulk transfer, battery, firmware … unchanged for brevity
  // -------------------------------------------------------------------------
  // (keep your existing bulkTransfer, battery read, RSSI timer, etc.)

  // ─── Internal ────────────────────────────────────────────────────────────
  Future<void> _ensurePermissions() async {
    final res = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (res.values.any((s) => !s.isGranted)) {
      throw 'Bluetooth permissions not granted';
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    _device = d;
    _connSub = d.connectionState.listen(_onConnectionChange);

    _connecting = true;
    await d.connect(autoConnect: false, mtu: 247);
    _connecting = false;

    // ── Discover characteristics
    for (final s in await d.discoverServices()) {
      if (s.uuid == _serviceUuid) {
        for (final c in s.characteristics) {
          if (c.uuid == _dataUuid) {
            _dataChar = c;
            await _ensureNotifying(c);
          } else if (c.uuid == _commandUuid) {
            _cmdChar = c;
          }
        }
      }
    }
    if (_dataChar == null || _cmdChar == null) {
      throw 'Required characteristics not found';
    }

    _connCtrl.add(PenConnection.connected);
  }

  Future<void> _ensureNotifying(BluetoothCharacteristic c) async {
    if (!c.isNotifying) await c.setNotifyValue(true);
  }

  void _onConnectionChange(BluetoothConnectionState s) {
    if (s == BluetoothConnectionState.disconnected) {
      _connCtrl.add(PenConnection.disconnected);
      _reconnect();
    }
  }

  Future<void> _reconnect() async {
    if (_device == null || _connecting) return;
    var delay = const Duration(seconds: 1);
    while (!isConnected) {
      await Future.delayed(delay);
      try {
        await _device!.connect(autoConnect: false, timeout: const Duration(seconds: 10));
      } on FlutterBluePlusException {
        delay *= 2;
        if (delay > const Duration(seconds: 32)) break;
      }
    }
  }

  Future<void> _sendCommand(int code) async {
    return;
    if (_cmdChar != null) await _cmdChar!.write([code]);
  }

  void _cleanUp() {
    _dataSub?.cancel();
    _connSub?.cancel();
    _device = null;
    _dataChar = null;
    _infoSub?.cancel();
    _cmdChar = null;
    _connCtrl.add(PenConnection.disconnected);
  }

  int? _lastRssi;                       // cached dBm value
  int?  get currentRssi => _lastRssi;   // expose to widgets

  Future<int?> readRssi() async {
    if (!isConnected) return null;
    try {
      _lastRssi = await _device!.readRssi();
    } catch (_) {
      _lastRssi = null;                 // read failed (e.g. disconnected)
    }
    return _lastRssi;
  }
}

