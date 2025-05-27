import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/my_bluetooth_service.dart';

/// Global singleton – every part of the app gets the very same instance.
final bluetoothServiceProvider = Provider<MyBluetoothService>((_) {
  return MyBluetoothService(); // factory returns the singleton
});

/// Reactive connection state (scanning / connected / disconnected).
final connectionProvider =
StreamProvider<PenConnection>((ref) => ref.read(bluetoothServiceProvider).connectionStream);

final rssiProvider = StreamProvider<int?>((ref) async* {
  final ble = ref.watch(bluetoothServiceProvider);

  // poll only while we are connected
  while (true) {
    if (ble.isConnected) {
      yield await ble.readRssi();          // emits dBm value or null
    } else {
      yield null;                          // show “--” in the UI
    }
    await Future.delayed(const Duration(seconds: 1));
  }
});