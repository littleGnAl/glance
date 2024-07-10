import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';

abstract class GlanceStackTrace {}

abstract class GlanceReporter<T> {
  void report(T info);
}

abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

class JankReport {
  const JankReport({
    required this.stackTrace,
    required this.frameTimings,
  });
  final GlanceStackTrace stackTrace;
  final List<FrameTiming> frameTimings;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is JankReport &&
        stackTrace == other.stackTrace &&
        listEquals(frameTimings, other.frameTimings);
  }

  @override
  int get hashCode => Object.hash(stackTrace, Object.hashAll(frameTimings));

  @override
  String toString() {
    return stackTrace.toString();
  }
}

class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = kDefaultJankThreshold,
    this.reporters = const [],
    this.modulePathFilters = kDefaultModulePathFilters,
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
  });
  final int jankThreshold;
  final List<GlanceReporter> reporters;

  /// e.g., libapp.so, libflutter.so
  final List<String> modulePathFilters;

  final int sampleRateInMilliseconds;
}

abstract class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= GlanceImpl();
    return _instance!;
  }

  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()});

  Future<void> end();
}
