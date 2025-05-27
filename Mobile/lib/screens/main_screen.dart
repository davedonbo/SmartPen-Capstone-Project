import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/my_bluetooth_service.dart';
import 'notes_screen.dart';
import 'live_capture_screen.dart';
import 'status_screen.dart';
import 'settings_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});
  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _idx = 0;
  StreamSubscription? _sleepSub;

  static const _titles = [
    'SmartPen Notebook',
    'Live Write',
    'SmartPen Status',
    'SmartPen Settings'
  ];

  late final _pages = [
    const NotesScreen(),
    const LiveCaptureScreen(),
    const StatusScreen(),
    const SettingsScreen()
  ];

  @override
  void initState() {
    super.initState();
    // One-time BLE initialise
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bluetoothServiceProvider).initialize();

      final ble = ref.read(bluetoothServiceProvider);
      ble.initialize();

      late final Timer _ticker;
        _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
          final ret = ble.listenForInfoSleep(_onSleep);

          if(ret!=null) {
            _sleepSub = ret;
            _ticker.cancel();
          };
        });



    });

  }

  void _onSleep() {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Battery Saving Mode'),
        content: const Text('SmartPen has gone to sleep due to inactivity'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Okay')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sleepSub?.cancel();     // 👈 NEW
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionProvider);

    conn.whenOrNull(
      data: (s) {
        var msg = switch (s) {
          PenConnection.connected   => 'SmartPen connected',
          PenConnection.disconnected => 'SmartPen disconnected',
          _                          => null
        };

        if (msg != null && mounted) {
          // 👇 wait until the frame is rendered (Scaffold exists)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text(msg!)));
          });
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_idx])),
      body: _pages[_idx],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        onTap: (i) => setState(() => _idx = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.note), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Live Write'),
          BottomNavigationBarItem(icon: Icon(Icons.device_hub), label: 'Status'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

}
