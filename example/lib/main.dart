import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glance/glance.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class MyJankDetectedReporter extends JankDetectedReporter {
  @override
  void report(JankReport info) {
    compute((msg) async {
      final token = (msg as List)[0];
      final info = (msg as List)[1];
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

      final docDir = await getExternalStorageDirectory();
      final stacktraceFilePath = path.join(
        docDir!.absolute.path,
        'jank_trace',
        'jank_trace_${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      // We want to print the log in non-debug mode
      // ignore: avoid_print
      print('[MyJankDetectedReporter] stacktraceFilePath: $stacktraceFilePath');
      final file = File(stacktraceFilePath);
      file.createSync(recursive: true);
      File(stacktraceFilePath).writeAsStringSync(
        info.stackTrace.toString(),
        flush: true,
      );
    }, [RootIsolateToken.instance, info]);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // myErrorsHandler.onErrorDetails(details);
    print(details.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // myErrorsHandler.onError(error, stack);
    print('$error\n$stack');
    return true;
  };

  _startGlance();
  runApp(const MyApp());
}

Future<void> _startGlance() async {
  Glance.instance.start(
    config: GlanceConfiguration(
      reporters: [MyJankDetectedReporter()],
    ),
  );

  await Permission.storage.request();
}

class MyApp extends StatelessWidget {
  // ignore: use_super_parameters
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      showPerformanceOverlay: true,
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  // ignore: use_super_parameters
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    final watch = Stopwatch();
    watch.start();
    for (int i = 0; i < 1000; ++i) {
      jsonEncode({
        for (int i = 0; i < 10000; ++i) 'aaa': 0,
      });
    }
    watch.stop();
    // ignore: avoid_print
    print('[_incrementCounter] spent: ${watch.elapsedMilliseconds}');
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text('$_counter'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
