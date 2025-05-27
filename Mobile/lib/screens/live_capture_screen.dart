import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../models/note.dart';
import '../services/my_bluetooth_service.dart';
import '../services/note_storage_service.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  final Note? note;
  const LiveCaptureScreen({super.key, this.note});
  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureState();
}

class _LiveCaptureState extends ConsumerState<LiveCaptureScreen> {
  late Note _note;
  final _ctrl = TextEditingController();
  StreamSubscription<PenConnection>? _connSub;
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note ?? Note();
    _ctrl.text = _note.content;

    final ble = ref.read(bluetoothServiceProvider);

    if (ble.isConnected && !_recording) {
      ble.startLiveCapture(_onChar);
      _recording = true;                // no setState – initState runs before build
    }

    _connSub = ble.connectionStream.listen((s) {
      if (s == PenConnection.connected && !_recording) {
        ble.startLiveCapture(_onChar);
        setState(() => _recording = true);
      } else if (s == PenConnection.disconnected && _recording) {
        setState(() => _recording = false);
      }
    });
  }

  void _onChar(String c) {
    if (!mounted) return;
    final sel = _ctrl.selection;
    final idx = sel.isValid ? sel.start : _ctrl.text.length;
    final newText = _ctrl.text.replaceRange(idx, idx, c);
    _ctrl.text = newText;
    _ctrl.selection = TextSelection.collapsed(offset: idx + 1);
    _note.content = newText;
    setState(() {});
  }

  @override
  void dispose() {
    ref.read(bluetoothServiceProvider).stopLiveCapture();
    _connSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: FloatingActionButton(
        heroTag: 'toggleCapture',
        onPressed: () {
          final ble = ref.read(bluetoothServiceProvider);
          if (_recording) {
            ble.stopLiveCapture();
          } else {
            ble.startLiveCapture(_onChar);
          }
          setState(() => _recording = !_recording);
        },
        child: Icon(_recording ? Icons.stop : Icons.play_arrow),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: TextField(
                    controller: _ctrl,
                    onChanged: (t) => _note.content = t,
                    maxLines: null,
                    autofocus: true,
                    style: const TextStyle(fontFamily: 'RobotoMono', fontSize: 20),
                    decoration:
                    const InputDecoration(border: InputBorder.none, isCollapsed: true),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.backspace),
                  onPressed: () {
                    if (_note.content.isNotEmpty) {
                      setState(() {
                        _note.content = _note.content.substring(0, _note.content.length - 1);
                        _ctrl.text = _note.content;
                      });
                    }
                  },
                ),
                IconButton.filled(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.delete),
                  onPressed: () => setState(() {
                    _note = Note();
                    _ctrl.clear();
                  }),
                ),
                IconButton.filled(
                  tooltip: 'Save',
                  icon: const Icon(Icons.save),
                  onPressed: _save,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_note.content.trim().isEmpty) return;
    final titleCtrl = TextEditingController(text: _note.title);
    final ok =       await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Note title'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(hintText: 'Untitled'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(_, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    _note.title = titleCtrl.text.trim();
    if (widget.note == null) {
      await NoteStorage.add(_note);
    } else {
      await _note.save();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved')));
    if (Navigator.canPop(context)) Navigator.pop(context);
  }
}
