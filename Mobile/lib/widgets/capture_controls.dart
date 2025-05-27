import 'package:flutter/material.dart';

class CaptureControls extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onClear;

  const CaptureControls({
    super.key,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save Note'),
            onPressed: onSave,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}