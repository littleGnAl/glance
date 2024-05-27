import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

import '_test_runner.dart';
import 'jank_app.dart';

class TouchEventJankWidget extends StatefulWidget {
  // ignore: use_super_parameters
  const TouchEventJankWidget({Key? key}) : super(key: key);

  @override
  State<TouchEventJankWidget> createState() => TouchEventJankWidgetState();
}

class TouchEventJankWidgetState extends State<TouchEventJankWidget> {
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
            child: const Text('increment'),
          ),
        ],
      ),
    );
  }
}

void main() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // ignore: avoid_print
    print('FlutterError.onError:\n${details.toString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    // ignore: avoid_print
    print('PlatformDispatcher.instance.onError:\n$error\n$stack');
    return true;
  };

  glanceIntegrationTest(() async {
    final binding = GlanceWidgetBinding.ensureInitialized();

    final globalKey = GlobalKey<TouchEventJankWidgetState>();
    Completer<String>? stackTraceCompleter;
    final reporter = TestJankDetectedReporter((info) {
      if (stackTraceCompleter != null && !stackTraceCompleter.isCompleted) {
        stackTraceCompleter.complete(info.stackTrace.toString());
      }
    });

    runApp(JankApp(
      builder: (c) => TouchEventJankWidget(key: globalKey),
    ));

    await binding.waitUntilFirstFrameRasterized;

    await Glance.instance.start(
      config: GlanceConfiguration(
        reporters: [reporter],
        jankThreshold: 5,
      ),
    );

    final offset = globalKey.currentState!._getElevatedButtonOffset();

    // Simulate click the button
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      position: (offset + const Offset(10, 10)),
    ));
    await Future.delayed(const Duration(milliseconds: 500));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      position: (offset + const Offset(10, 10)),
    ));

    stackTraceCompleter = Completer();

    final stackTraces = await stackTraceCompleter.future;

    checkStackTraces(stackTraces);
  });
}
