// lib/services/note_storage_service.dart
import 'package:hive/hive.dart';
import '../models/note.dart';

class NoteStorage {
  static final _box = Hive.box<Note>('notes');

  static List<Note> all() => _box.values.toList();

  static Future<int> add(Note note) => _box.add(note);

  static Future<void> delete(Note note) => note.delete();
}
