import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

class TestJankDetectedReporter extends JankDetectedReporter {
  TestJankDetectedReporter(this.onReport);
  final void Function(JankReport info) onReport;
  @override
  void report(JankReport info) {
    // compute((msg) async {
    //   final (token, info) = msg;
    //   BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

    //   final docDir = await getExternalStorageDirectory();
    //   final stacktraceFilePath = path.join(
    //     docDir!.absolute.path,
    //     'jank_trace',
    //     'jank_trace_${DateTime.now().microsecondsSinceEpoch}.json',
    //   );
    //   print('addJankCallback stacktraceFilePath: ${stacktraceFilePath}');
    //   final file = File(stacktraceFilePath);
    //   file.createSync(recursive: true);
    //   File(stacktraceFilePath).writeAsStringSync(
    //     jsonEncode(info.toString()),
    //     flush: true,
    //   );
    // }, (RootIsolateToken.instance, info));

    onReport(info);
  }
}

// void main() async {
//   _startGlance();
//   runApp(const MyApp());
// }

// Future<void> _startGlance() async {
//   // WidgetsFlutterBinding.ensureInitialized();
//   // Glance.instance.start(
//   //     config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));

//   // await Permission.storage.request();
// }

@pragma("vm:never-inline")
void expensiveFunction() {
  final watch = Stopwatch();
  watch.start();
  for (int i = 0; i < 1000; ++i) {
    jsonEncode({
      for (int i = 0; i < 10000; ++i) 'aaa': 0,
    });
  }
  watch.stop();
  print('[expensiveFunction]: ${watch.elapsedMilliseconds}');
}

class JankApp extends StatelessWidget {
  const JankApp({Key? key, required this.builder}) : super(key: key);

  final WidgetBuilder builder;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: builder(context),
      ),
    );
  }
}
