import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glance/glance.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

import 'binding.dart';

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

Future<void> _startGlance() async {
  // WidgetsFlutterBinding.ensureInitialized();
  // Glance.instance.start(
  //     config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));

  // await Permission.storage.request();
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

class VsyncPhaseJankWidget extends StatefulWidget {
  const VsyncPhaseJankWidget({Key? key}) : super(key: key);

  @override
  State<VsyncPhaseJankWidget> createState() => VsyncPhaseJankWidgetState();
}

class VsyncPhaseJankWidgetState extends State<VsyncPhaseJankWidget> {
  int _counter = 0;

  void _incrementCounter() {
    print('kjkjkjjkjkjk');
    final watch = Stopwatch();
    watch.start();
    for (int i = 0; i < 1000; ++i) {
      jsonEncode({
        for (int i = 0; i < 10000; ++i) 'aaa': 0,
      });
    }
    Timeline.now;
    watch.stop();
    print('_incrementCounter time spend: ${watch.elapsedMilliseconds}');
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      // Center is a layout widget. It takes a single child and positions it
      // in the middle of the parent.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Text(
            'You have pushed the button this many times:',
          ),
          Text('$_counter'),
          ElevatedButton(
            key: const ValueKey('increment'),
            onPressed: _incrementCounter,
            child: const Text('increment'),
          ),
        ],
      ),
    );
  }
}

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final binding =
      GlanceIntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("vsync phase jank", (WidgetTester tester) async {
    final Completer<String> stackTraceCompleter = Completer();
    final List<String> stackTraces = [];
    final reporter = TestJankDetectedReporter((info) {
      // if (!stackTraceCompleter.isCompleted) {
      //   stackTraceCompleter.complete(info.stackTrace.toString());
      // }

      stackTraces.add(info.stackTrace.toString());
    });
    Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
    runApp(JankApp(
      builder: (c) => VsyncPhaseJankWidget(),
    ));
    await tester.pumpAndSettle();

    // Smoke smoke check
    expect(find.text('0'), findsOneWidget);
    final button = find.byKey(const ValueKey('increment'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    print('bbbb');

    // final stackTrace = await stackTraceCompleter.future;

    await binding.checkStackTrace('vsync_phase_jank', stackTraces.join('\n'));
    print('aaaa:\n ${stackTraces}');
  });

  testWidgets("build phase jank", (WidgetTester tester) async {
    // expect(2 + 2, equals(5));
  });
}
