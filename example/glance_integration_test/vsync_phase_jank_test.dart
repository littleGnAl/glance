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

void main() {
  glanceIntegrationTest(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final globalKey = GlobalKey<VsyncPhaseJankWidgetState>();
    Completer<String>? stackTraceCompleter;
    final reporter = TestJankDetectedReporter((info) {
      if (stackTraceCompleter != null && !stackTraceCompleter.isCompleted) {
        stackTraceCompleter.complete(info.stackTrace.toString());
      }
    });
    Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
    runApp(JankApp(
      builder: (c) => VsyncPhaseJankWidget(key: globalKey),
    ));

    await binding.waitUntilFirstFrameRasterized;

    final offset = globalKey.currentState!._getElevatedButtonOffset();

    stackTraceCompleter = Completer();
    // Simulate click the button
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      position: (offset + const Offset(10, 10)),
    ));
    await Future.delayed(const Duration(milliseconds: 500));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      position: (offset + const Offset(10, 10)),
    ));

    final stackTraces = await stackTraceCompleter.future;

    checkStackTraces(stackTraces);
  });
}
