import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../widgets/rssiIcon.dart';

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.read(bluetoothServiceProvider);

    // RSSI ticker every second + connection changes
    final merged = StreamGroup.merge([
      ble.connectionStream.map((_) => 0),
      Stream.periodic(const Duration(seconds: 1)),
    ]);

    return StreamBuilder(
      stream: merged,
      builder: (_, __) {
        final connected = ble.isConnected;
        return Scaffold(
          body: ListView(
            children: [
              ListTile(
                leading: Icon(Icons.bluetooth, color: connected ? Colors.green : Colors.red),
                title: Text(connected ? 'Connected' : 'Disconnected'),
                // subtitle: Text('RSSI: ${ref.watch(rssiProvider).value} dBm'),
              ),
              ListTile(
                leading: RssiIcon(rssi: ref.watch(rssiProvider).value),
                title: const Text('Signal Strength'),
                subtitle: Text(
                  ref.watch(rssiProvider).when(
                    data: (v)  => v != null ? '$v dBm' : '--',
                    loading:   () => '…',
                    error:     (_, __) => '--',
                  ),
                ),
              ),
              // ListTile(
              //   leading: const Icon(Icons.battery_full),
              //   title: const Text('Battery'),
              //   // subtitle: Text('${ble.batteryPercent ?? "--"} %'),
              // ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('Pen storage'),
                subtitle: Text('0 / 300 KB'),
              ),
              ListTile(
                leading: const Icon(Icons.tag),
                title: const Text('Firmware'),
                subtitle: Text("Smart Pen v1.0.0"),
              ),
            ],
          ),
        );
      },
    );
  }


}
