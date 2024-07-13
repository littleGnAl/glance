import 'dart:async';

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

import '_test_runner.dart';
import 'jank_app.dart';

class VsyncPhaseJankWidget extends StatefulWidget {
  // ignore: use_super_parameters
  const VsyncPhaseJankWidget({Key? key}) : super(key: key);

  @override
  State<VsyncPhaseJankWidget> createState() => VsyncPhaseJankWidgetState();
}

class VsyncPhaseJankWidgetState extends State<VsyncPhaseJankWidget> {
  int _counter = 0;

  // final WidgetStatesController _statesController = WidgetStatesController();

  final GlobalKey _buttonKey = GlobalKey();

  Offset _getElevatedButtonOffset() {
    RenderBox box = _buttonKey.currentContext!.findRenderObject() as RenderBox;
    Offset position = box.localToGlobal(Offset.zero);
    return position;
  }

  void _incrementCounter() {
    expensiveFunction();
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

// void _vsyncPhaseJank() async {
//   final binding = WidgetsFlutterBinding.ensureInitialized();
//   final globalKey = GlobalKey<VsyncPhaseJankWidgetState>();
//   Completer<String>? stackTraceCompleter;
//   final List<String> stackTraces = [];

//   bool finishNextTime = false;
//   final reporter = TestJankDetectedReporter((info) {
//     // if (!stackTraceCompleter.isCompleted) {
//     //   stackTraceCompleter.complete(info.stackTrace.toString());
//     // }

//     // stackTraces.add(info.stackTrace.toString());

//     // print('[glance_test] Collect stack traces start');
//     // info.stackTrace.toString().split('\n').forEach((e) {
//     //   print(e);
//     // });
//     // print('[glance_test] Collect stack traces end');

//     // if (finishNextTime) {
//     //   print('[glance_test_finished]');
//     // }

//     if (stackTraceCompleter != null && !stackTraceCompleter!.isCompleted) {
//       stackTraces.add(info.stackTrace.toString());
//       stackTraceCompleter!.complete(stackTraces.join('\n'));
//     }
//   });
//   Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
//   runApp(JankApp(
//     builder: (c) => VsyncPhaseJankWidget(key: globalKey),
//   ));

//   await binding.waitUntilFirstFrameRasterized;

//   await Future.delayed(Duration(milliseconds: 5000));

//   // globalKey.currentState?._statesController
//   //     .update(WidgetState.pressed, true); //_incrementCounter();
//   // await Future.delayed(Duration(milliseconds: 200));
//   // globalKey.currentState?._statesController.update(WidgetState.pressed, false);

//   final offset = globalKey.currentState!._getElevatedButtonOffset();
//   print('offset: ${offset.dx}, ${offset.dy}');
//   // GestureBinding.instance.handlePointerEvent(PointerUpEvent(
//   //   position: (offset + Offset(10, 10)),
//   // ));

//   stackTraceCompleter = Completer();
//   GestureBinding.instance.handlePointerEvent(PointerDownEvent(
//     position: (offset + Offset(10, 10)),
//   ));
//   await Future.delayed(const Duration(milliseconds: 500));
//   GestureBinding.instance.handlePointerEvent(PointerUpEvent(
//     position: (offset + Offset(10, 10)),
//   ));

//   // [glance_test_finished]

//   finishNextTime = true;

//   await stackTraceCompleter.future;

//   // print('[glance_test] Collect stack traces start');
//   StringBuffer sb = StringBuffer();
//   stackTraces.forEach((e) {
//     sb.writeln(e);
//   });
//   // sb.toString().split('\n').forEach((e) {
//   //   print(e);
//   // });
//   // print('[glance_test] Collect stack traces end');

//   checkStackTraces(sb.toString());

//   // print('[glance_test_finished]');

//   // if (finishNextTime) {
//   //   print('[glance_test_finished]');
//   // }
// }

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // final binding =
  //     GlanceIntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // _testCases['vsync_phase_jank']!();

  glanceIntegrationTest(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final globalKey = GlobalKey<VsyncPhaseJankWidgetState>();
    Completer<String>? stackTraceCompleter;
    // final List<String> stackTraces = [];

    // bool finishNextTime = false;
    final reporter = TestJankDetectedReporter((info) {
      // if (!stackTraceCompleter.isCompleted) {
      //   stackTraceCompleter.complete(info.stackTrace.toString());
      // }

      // stackTraces.add(info.stackTrace.toString());

      // print('[glance_test] Collect stack traces start');
      // info.stackTrace.toString().split('\n').forEach((e) {
      //   print(e);
      // });
      // print('[glance_test] Collect stack traces end');

      // if (finishNextTime) {
      //   print('[glance_test_finished]');
      // }

      if (stackTraceCompleter != null && !stackTraceCompleter.isCompleted) {
        // stackTraces.add(info.stackTrace.toString());
        stackTraceCompleter.complete(info.stackTrace.toString());
      }
    });
    Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
    runApp(JankApp(
      builder: (c) => VsyncPhaseJankWidget(key: globalKey),
    ));

    await binding.waitUntilFirstFrameRasterized;

    // await Future.delayed(const Duration(milliseconds: 5000));

    // globalKey.currentState?._statesController
    //     .update(WidgetState.pressed, true); //_incrementCounter();
    // await Future.delayed(Duration(milliseconds: 200));
    // globalKey.currentState?._statesController.update(WidgetState.pressed, false);

    final offset = globalKey.currentState!._getElevatedButtonOffset();
    // print('offset: ${offset.dx}, ${offset.dy}');
    // GestureBinding.instance.handlePointerEvent(PointerUpEvent(
    //   position: (offset + Offset(10, 10)),
    // ));

    stackTraceCompleter = Completer();
    // Simulate click the button
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      position: (offset + const Offset(10, 10)),
    ));
    await Future.delayed(const Duration(milliseconds: 500));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      position: (offset + const Offset(10, 10)),
    ));

    // [glance_test_finished]

    // finishNextTime = true;

    final stackTraces = await stackTraceCompleter.future;

    // print('[glance_test] Collect stack traces start');
    // StringBuffer sb = StringBuffer();
    // stackTraces.forEach((e) {
    //   sb.writeln(e);
    // });
    // sb.toString().split('\n').forEach((e) {
    //   print(e);
    // });
    // print('[glance_test] Collect stack traces end');

    checkStackTraces(stackTraces);
  });

  // _vsyncPhaseJank();
}
