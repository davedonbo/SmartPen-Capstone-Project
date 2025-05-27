import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../models/note.dart';
import '../providers.dart';
import '../services/my_bluetooth_service.dart';
import '../services/theme_controller.dart';
import '../services/note_storage_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _auto = true;
  late final ThemeController _tc;

  @override
  void initState() {
    super.initState();
    _tc = ThemeController.instance;
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.read(bluetoothServiceProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            elevation: 4,
            child: ListTile(
              leading: const Icon(Icons.cloud_download, size: 32),
              title: const Text('Bulk transfer notes', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Import everything on the device'),
              onTap: () => _bulkTransfer(ble),
            ),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Auto-connect on launch'),
            value: _auto,
            onChanged: (v) => setState(() => _auto = v),
          ),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(_tc.mode.name),
            onTap: () => showModalBottomSheet(
              context: context,
              builder: (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: ThemeMode.values.map((m) {
                  return RadioListTile(
                    title: Text(m.name),
                    value: m,
                    groupValue: _tc.mode,
                    onChanged: (v) {
                      Navigator.pop(context);
                      _tc.setMode(v as ThemeMode);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Export all notes'),
            onTap: () {/* TODO share_plus */},
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Delete all notes'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Delete everything?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
                    ElevatedButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true) await Hive.box<Note>('notes').clear();
            },
          ),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: 'SmartPen Notebook',
            applicationVersion: '1.0.0',
            applicationLegalese: '© 2025 My Team',
          ),
        ],
      ),
    );
  }

  Future<void> _bulkTransfer(MyBluetoothService ble) async {
    if (!ble.isConnected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pen not connected')));
      return;
    }
    int imported = 0;
    bool cancelled = false;

    // show modal progress dialog
    await showDialog(
      barrierDismissible: false,
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Bulk transfer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('Imported $imported note${imported == 1 ? '' : 's'}…'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    // actually run the transfer after dialog shows (avoids layout delay)
    // await _ble.bulkTransfer(
    //   onChunk: (txt) async {
    //     imported++;
    //     await NoteStorage.add(Note(content: txt));
    //     // update dialog text
    //     if (context.mounted) {
    //       (Navigator.of(context).overlay!.context as Element).markNeedsBuild();
    //     }
    //   },
    //   onDone: () {
    //     if (Navigator.canPop(context)) Navigator.pop(context);
    //   },
    //   onCancel: () {
    //     cancelled = true;
    //     if (Navigator.canPop(context)) Navigator.pop(context);
    //   },
    // );

    if (!cancelled && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $imported note${imported == 1 ? '' : 's'}'),
        ),
      );
    }
  }
}
