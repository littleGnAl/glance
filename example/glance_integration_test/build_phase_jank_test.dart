import 'dart:async';

import 'package:flutter/foundation.dart';
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

  Future<void> triggerExpensiveBuild() async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    setState(() {
      _isExpensiveBuild = true;
    });
  }

  @override
  void initState() {
    super.initState();

    triggerExpensiveBuild();
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpensiveBuild) {
      expensiveFunction();
    }
    return const SizedBox();
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
      ),
    );

    runApp(JankApp(
      builder: (c) => const BuildPhaseJankWidget(),
    ));
  });
}
