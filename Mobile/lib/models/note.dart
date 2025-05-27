// lib/models/note.dart
import 'package:hive/hive.dart';
part 'note.g.dart';                // ← code-gen file

@HiveType(typeId: 0)
class Note extends HiveObject {
  @HiveField(0) String title;
  @HiveField(1) String content;
  @HiveField(2) DateTime createdAt;

  Note({
    this.title = '',
    this.content = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get formattedDate =>
      '${createdAt.month}/${createdAt.day}/${createdAt.year}';
}
