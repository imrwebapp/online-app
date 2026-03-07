import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global in-memory log buffer — add to it from anywhere in the app.
/// Shows the last [maxLines] lines so it never grows unbounded.
class AppLogger {
  static const int maxLines = 200;
  static final List<String> _lines = [];
  static final _notifier = ValueNotifier<int>(0);

  static ValueNotifier<int> get notifier => _notifier;
  static List<String> get lines => List.unmodifiable(_lines);

  static void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23); // HH:mm:ss.mmm
    final entry = '[$ts] $msg';
    debugPrint(entry); // still prints to console when available
    _lines.add(entry);
    if (_lines.length > maxLines) _lines.removeAt(0);
    _notifier.value++;
  }

  static void clear() {
    _lines.clear();
    _notifier.value++;
  }
}

/// Full-screen scrollable log viewer.
/// Add a button somewhere in your app to navigate to this screen:
///
///   Navigator.push(context, MaterialPageRoute(builder: (_) => DebugLogScreen()));
///
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    AppLogger.notifier.addListener(_onNewLog);
  }

  @override
  void dispose() {
    AppLogger.notifier.removeListener(_onNewLog);
    _scroll.dispose();
    super.dispose();
  }

  void _onNewLog() {
    setState(() {});
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.lines;

    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213e),
        title: const Text(
          '🪲 Debug Logs',
          style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white),
            tooltip: 'Copy all',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: lines.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Clear',
            onPressed: () {
              AppLogger.clear();
              setState(() {});
            },
          ),
        ],
      ),
      body: lines.isEmpty
          ? const Center(
              child: Text(
                'No logs yet.\nTap Play on a surah to begin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final line = lines[i];
                Color color = Colors.greenAccent;
                if (line.contains('❌') || line.contains('ERROR')) {
                  color = Colors.redAccent;
                } else if (line.contains('⚠️') || line.contains('WARN')) {
                  color = Colors.orangeAccent;
                } else if (line.contains('✅')) {
                  color = Colors.lightGreenAccent;
                } else if (line.contains('▶️') || line.contains('🎵')) {
                  color = Colors.cyanAccent;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    line,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
    );
  }
}