import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/note.dart';
import '../providers.dart';
import '../widgets/connection_banner.dart';
import '../widgets/note_tile.dart';
import 'live_capture_screen.dart';

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LiveCaptureScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const ConnectionBanner(), // banner reads provider directly
          Expanded(
            child: ValueListenableBuilder<Box<Note>>(
              valueListenable: Hive.box<Note>('notes').listenable(),
              builder: (_, box, __) {
                final notes = box.values.toList().cast<Note>().reversed.toList();
                if (notes.isEmpty) return const _Empty();
                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 80,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (_, i) => NoteTile(note: notes[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.note_add, size: 96),
        SizedBox(height: 16),
        Text('No notes yet'),
        SizedBox(height: 8),
        Text('Tap  ➕  to start writing'),
      ],
    ),
  );
}
