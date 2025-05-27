import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/theme_controller.dart';
import 'models/note.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(NoteAdapter());
  await Hive.openBox<Note>('notes');

  final themeCtrl = ThemeController.instance;
  await themeCtrl.init();

  runApp(ProviderScope(child: MyApp(themeCtrl)));
}

class MyApp extends StatelessWidget {
  final ThemeController tc;
  const MyApp(this.tc, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tc,
      builder: (_, __) {
        return MaterialApp(
          title: 'SmartPen Notebook',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.blueGrey,
            brightness: Brightness.light,
            appBarTheme:
            const AppBarTheme(backgroundColor: Color(0xFF263238), elevation: 4),
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blueGrey,
            brightness: Brightness.dark,
            appBarTheme:
            const AppBarTheme(backgroundColor: Color(0xFF37474F), elevation: 4),
          ),
          themeMode: tc.mode,
          home: const MainScreen(),
        );
      },
    );
  }
}
