import 'package:flutter/material.dart';
import '../models/note.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';     // NEW
import '../services/note_storage_service.dart';              // delete helper
import '../screens/live_capture_screen.dart';

class NoteTile extends StatelessWidget {
  final Note note;

  const NoteTile({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
       return Slidable(
         key: ValueKey(note.key),
         endActionPane: ActionPane(
           motion: const DrawerMotion(),
           children: [
             SlidableAction(
               onPressed: (_) => _edit(context),
               icon: Icons.edit,
               backgroundColor: Colors.blueGrey,
               label: 'Edit',
             ),
             SlidableAction(
               onPressed: (_) => _delete(context),
               icon: Icons.delete,
               backgroundColor: Colors.red,
               label: 'Delete',
             ),
           ],
         ),
         child: ListTile(
           title: Text(
             note.title.trim().isEmpty ? 'Untitled Note' : note.title.trim()),
           subtitle: Text(
             note.content,
             maxLines: 1,
             overflow: TextOverflow.ellipsis,
           ),
           trailing: Text(DateFormat('MMM dd').format(note.createdAt)),
           onTap: () => _showNoteDetails(context),
         ),
       );
  }

  void _showNoteDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note.title),
        content: SingleChildScrollView(child: Text(note.content)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

   void _delete(BuildContext context) async {
       final ok = await showDialog<bool>(
         context: context,
         builder: (_) => AlertDialog(
           title: const Text('Delete note?'),
           content: const Text('This action cannot be undone.'),
           actions: [
             TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
             ElevatedButton(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
           ],
         ),
       );
       if (ok == true) await NoteStorage.delete(note);   // Hive delete
     }

   void _edit(BuildContext context) {
       Navigator.push(
             context,
             MaterialPageRoute(builder: (_) => LiveCaptureScreen(note: note)),
           );
     }


}