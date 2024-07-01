import 'dart:async';

import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

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

// Map<String, void Function()> _testCases = {
//   'vsync_phase_jank': _vsyncPhaseJank,
//   'build_phase_jank': _buildPhaseJank,
// };

void main() {
  // IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // final binding =
  //     GlanceIntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // _testCases['vsync_phase_jank']!();

  _buildPhaseJank();
}
