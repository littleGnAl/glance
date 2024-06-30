import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
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

void _expensiveFunction() {
  print('kjkjkjjkjkjk');
  final watch = Stopwatch();
  watch.start();
  for (int i = 0; i < 1000; ++i) {
    jsonEncode({
      for (int i = 0; i < 10000; ++i) 'aaa': 0,
    });
  }
  watch.stop();
  print('_expensiveFunction time spend: ${watch.elapsedMilliseconds}');
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

  // final WidgetStatesController _statesController = WidgetStatesController();

  GlobalKey _buttonKey = GlobalKey();

  Offset _getElevatedButtonOffset() {
    RenderBox box = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    Offset position = box.localToGlobal(Offset.zero); //this is global position
    return position;
  }

  void _incrementCounter() {
    _expensiveFunction();
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
            key: _buttonKey,
            onPressed: _incrementCounter,
            // statesController: _statesController,
            child: const Text('increment'),
          ),
        ],
      ),
    );
  }
}

class BuildPhaseJankWidget extends StatefulWidget {
  const BuildPhaseJankWidget({super.key});

  @override
  State<BuildPhaseJankWidget> createState() => _BuildPhaseJankWidgetState();
}

class _BuildPhaseJankWidgetState extends State<BuildPhaseJankWidget> {
  bool _isExpensiveBuild = false;

  void triggerExpensiveBuild() {
    setState(() {
      _isExpensiveBuild = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpensiveBuild) {
      _expensiveFunction();
    }
    return const SizedBox();
  }
}

void _vsyncPhaseJank() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final globalKey = GlobalKey<VsyncPhaseJankWidgetState>();
  final Completer<String> stackTraceCompleter = Completer();
  final List<String> stackTraces = [];

  bool finishNextTime = false;
  final reporter = TestJankDetectedReporter((info) {
    // if (!stackTraceCompleter.isCompleted) {
    //   stackTraceCompleter.complete(info.stackTrace.toString());
    // }

    // stackTraces.add(info.stackTrace.toString());

    print('[glance_test] Collect stack traces start');
    info.stackTrace.toString().split('\n').forEach((e) {
      print(e);
    });
    print('[glance_test] Collect stack traces end');

    if (finishNextTime) {
      print('[glance_test_finished]');
    }
  });
  Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
  runApp(JankApp(
    builder: (c) => VsyncPhaseJankWidget(key: globalKey),
  ));

  await binding.waitUntilFirstFrameRasterized;

  await Future.delayed(Duration(milliseconds: 5000));

  // globalKey.currentState?._statesController
  //     .update(WidgetState.pressed, true); //_incrementCounter();
  // await Future.delayed(Duration(milliseconds: 200));
  // globalKey.currentState?._statesController.update(WidgetState.pressed, false);

  final offset = globalKey.currentState!._getElevatedButtonOffset();
  print('offset: ${offset.dx}, ${offset.dy}');
  // GestureBinding.instance.handlePointerEvent(PointerUpEvent(
  //   position: (offset + Offset(10, 10)),
  // ));

  GestureBinding.instance.handlePointerEvent(PointerDownEvent(
    position: (offset + Offset(10, 10)),
  ));
  await Future.delayed(const Duration(milliseconds: 500));
  GestureBinding.instance.handlePointerEvent(PointerUpEvent(
    position: (offset + Offset(10, 10)),
  ));

  // [glance_test_finished]

  finishNextTime = true;
}

void _buildPhaseJank() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final globalKey = GlobalKey<_BuildPhaseJankWidgetState>();
  final Completer<String> stackTraceCompleter = Completer();
  final List<String> stackTraces = [];

  bool finishNextTime = false;
  final reporter = TestJankDetectedReporter((info) {
    // if (!stackTraceCompleter.isCompleted) {
    //   stackTraceCompleter.complete(info.stackTrace.toString());
    // }

    // stackTraces.add(info.stackTrace.toString());

    print('[glance_test] Collect stack traces start');
    info.stackTrace.toString().split('\n').forEach((e) {
      print(e);
    });
    print('[glance_test] Collect stack traces end');

    if (finishNextTime) {
      print('[glance_test_finished]');
    }
  });
  Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
  runApp(JankApp(
    builder: (c) => BuildPhaseJankWidget(key: globalKey),
  ));

  await binding.waitUntilFirstFrameRasterized;

  await Future.delayed(Duration(milliseconds: 5000));

  // globalKey.currentState?._statesController
  //     .update(WidgetState.pressed, true); //_incrementCounter();
  // await Future.delayed(Duration(milliseconds: 200));
  // globalKey.currentState?._statesController.update(WidgetState.pressed, false);

  final offset = globalKey.currentState!.triggerExpensiveBuild();

  // GestureBinding.instance.handlePointerEvent(PointerDownEvent(
  //   position: (offset + Offset(10, 10)),
  // ));
  // await Future.delayed(const Duration(milliseconds: 500));
  // GestureBinding.instance.handlePointerEvent(PointerUpEvent(
  //   position: (offset + Offset(10, 10)),
  // ));

  // [glance_test_finished]

  finishNextTime = true;
}

Map<String, void Function()> _testCases = {
  'vsync_phase_jank': _vsyncPhaseJank,
  'build_phase_jank': _buildPhaseJank,
};

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // final binding =
  //     GlanceIntegrationTestWidgetsFlutterBinding.ensureInitialized();

  _testCases['vsync_phase_jank']!();
}
