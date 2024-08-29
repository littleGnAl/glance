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
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 5), () {
      _click();
    });
  }

  void _click() {
    final offset = _getElevatedButtonOffset();

    // Simulate click the button
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      position: (offset + const Offset(10, 10)),
    ));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      position: (offset + const Offset(10, 10)),
    ));
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
    GlanceWidgetBinding.ensureInitialized();

    final reporter = TestJankDetectedReporter((info) {
      checkStackTraces(info.stackTrace.toString());
    });
    await Glance.instance.start(
      config: GlanceConfiguration(
        reporters: [reporter],
        jankThreshold: 5,
      ),
    );

    runApp(JankApp(
      builder: (c) => const TouchEventJankWidget(),
    ));
  });
}
