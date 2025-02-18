import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:glance/glance.dart';

import 'package:glance/src/logger.dart';

class TestJankDetectedReporter extends JankDetectedReporter {
  TestJankDetectedReporter(this.onReport);
  final void Function(JankReport info) onReport;
  @override
  void report(JankReport info) {
    onReport(info);
  }
}

@pragma("vm:never-inline")
void expensiveFunction() {
  final watch = Stopwatch();
  watch.start();
  for (int i = 0; i < 1000; ++i) {
    jsonEncode({for (int i = 0; i < 10000; ++i) 'aaa': 0});
  }
  watch.stop();
  GlanceLogger.log(
    '[expensiveFunction]: ${watch.elapsedMilliseconds}',
    prefixTag: false,
  );
}

class JankApp extends StatelessWidget {
  // ignore: use_super_parameters
  const JankApp({Key? key, required this.builder}) : super(key: key);

  final WidgetBuilder builder;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: builder(context)));
  }
}
