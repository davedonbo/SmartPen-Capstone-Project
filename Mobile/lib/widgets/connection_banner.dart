import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/my_bluetooth_service.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final conn = ref.watch(connectionProvider).value ?? PenConnection.scanning;

    late Color bg;
    late IconData icon;
    late String txt;
    switch (conn) {
      case PenConnection.connected:
        bg = cs.secondaryContainer;
        icon = Icons.check_circle;
        txt = 'Connected';
        break;
      case PenConnection.disconnected:
        bg = cs.errorContainer;
        icon = Icons.cancel;
        txt = 'Disconnected';
        break;
      default:
        bg = cs.tertiaryContainer;
        icon = Icons.sync;
        txt = 'Scanning…';
    }

    return Material(
      color: bg,
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: ListTile(
          dense: true,
          leading: Icon(icon),
          title: Text(txt),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(bluetoothServiceProvider).connect(),
          ),
        ),
      ),
    );
  }
}
