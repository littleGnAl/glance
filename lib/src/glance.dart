import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';

/// Represents a stack trace used in [Glance]
abstract class GlanceStackTrace {}

/// Defines a reporter that can report specific information in [Glance].
abstract class GlanceReporter<T> {
  void report(T info);
}

/// A reporter specifically for reporting UI jank infomations.
abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

/// A report that contains information about detected jank, including the stack trace
/// and frame timings associated with the jank
class JankReport {
  const JankReport({
    required this.stackTrace,
    required this.frameTimings,
  });

  /// The stack traces captured when UI jank was detected.
  final GlanceStackTrace stackTrace;

  /// The `FrameTiming` from [SchedulerBinding.addTimingsCallback] when UI jank occur.
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
}

/// Configuration class for [Glance]
class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = kDefaultJankThreshold,
    this.reporters = const [],
    this.modulePathFilters = kDefaultModulePathFilters,
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
  });

  /// The threshold in milliseconds for detecting UI jank. Defaults to [kDefaultJankThreshold].
  final int jankThreshold;

  /// A list of reporters that will handle the reporting of UI jank.
  final List<GlanceReporter> reporters;

  /// Filters for module paths, such as `libapp.so` and `libflutter.so`.
  final List<String> modulePathFilters;

  /// The interval in milliseconds for capture the stack traces. Defaults to [kDefaultSampleRateInMilliseconds].
  /// Lower value will capture more accuracy stack traces, but will impace the performance.
  final int sampleRateInMilliseconds;
}

/// The [Glance] is a singleton class for handling  monitoring functionality of the UI jank detection.
///
/// You should implement you own [JankDetectedReporter] to receive the [JankReport].
/// After getting the [JankReport.stackTrace], you need to symbolize it using the built-in
/// symbolize tool(ee the [guide](https://github.com/littleGnAl/glance?tab=readme-ov-file#symbolize-the-glance-stack-traces) for more detail.)
/// You can save the stack traces to files, or upload to your server, and symbolize it later.
///
/// You can use all the default values of [GlanceConfiguration], see [GlanceConfiguration]
/// for more detail.
///
/// You can change the values to meet your requirements.
abstract class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= GlanceImpl();
    return _instance!;
  }

  /// Starts  monitoring UI jank with the given configuration.
  /// If no configuration is provided, the default configuration is used.
  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()});

  /// Ends the Glance monitoring.
  Future<void> end();
}
