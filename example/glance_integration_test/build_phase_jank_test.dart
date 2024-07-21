import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

import '_test_runner.dart';
import 'jank_app.dart';

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

  // Wrap the `expensiveFunction()` without inline, so that we can find the stack
  // more easier in the integration test.
  @pragma("vm:never-inline")
  void _expensiveFunction() {
    expensiveFunction();
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpensiveBuild) {
      _expensiveFunction();
    }
    return const SizedBox();
  }
}

void main() {
  glanceIntegrationTest(() async {
    final binding = WidgetsFlutterBinding.ensureInitialized();
    final globalKey = GlobalKey<_BuildPhaseJankWidgetState>();
    Completer<String>? stackTraceCompleter;
    final reporter = TestJankDetectedReporter((info) {
      if (stackTraceCompleter != null && !stackTraceCompleter.isCompleted) {
        stackTraceCompleter.complete(info.stackTrace.toString());
      }
    });
    Glance.instance.start(config: GlanceConfiguration(reporters: [reporter]));
    runApp(JankApp(
      builder: (c) => BuildPhaseJankWidget(key: globalKey),
    ));

    await binding.waitUntilFirstFrameRasterized;

    globalKey.currentState!.triggerExpensiveBuild();
    stackTraceCompleter = Completer();

    final stackTraces = await stackTraceCompleter.future;
    checkStackTraces(stackTraces);
  });
}
