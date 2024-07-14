import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';

/// Represents a stack trace used in Glance
abstract class GlanceStackTrace {}

/// Defines a reporter that can report specific information in Glance.
abstract class GlanceReporter<T> {
  void report(T info);
}

/// A reporter specifically for reporting jank (performance lag) incidents.
abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

/// A report that contains information about detected jank, including the stack trace
/// and frame timings associated with the jank
class JankReport {
  const JankReport({
    required this.stackTrace,
    required this.frameTimings,
  });

  /// The stack trace captured when jank was detected.
  final GlanceStackTrace stackTrace;

  /// The `FrameTiming` from [SchedulerBinding.addTimingsCallback] when jank occur.
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

/// Configuration class for Glance
class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = kDefaultJankThreshold,
    this.reporters = const [],
    this.modulePathFilters = kDefaultModulePathFilters,
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
  });

  /// The threshold in milliseconds for detecting jank. Defaults to [kDefaultJankThreshold].
  final int jankThreshold;

  /// A list of reporters that will handle the reporting of jank.
  final List<GlanceReporter> reporters;

  /// Filters for module paths, such as `libapp.so` and `libflutter.so`.
  final List<String> modulePathFilters;

  /// The sample rate in milliseconds for performance measurements. Defaults to [kDefaultSampleRateInMilliseconds].
  final int sampleRateInMilliseconds;
}

abstract class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= GlanceImpl();
    return _instance!;
  }

  /// Starts the Glance monitoring with the given configuration.
  /// If no configuration is provided, the default configuration is used.
  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()});

  /// Ends the Glance monitoring.
  Future<void> end();
}
