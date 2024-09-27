import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

/// A custom binding that connects [WidgetsFlutterBinding] and [Glance] to detect
/// UI jank during the build phase and from "external sources" such as callbacks from
/// [WidgetsBindingObserver], touch events, and channel messages from the platform.
class GlanceWidgetBinding extends WidgetsFlutterBinding
    with GlanceWidgetBindingMixin {
  GlanceWidgetBinding._();

  /// Get the singleton instance of [GlanceWidgetBinding]
  static GlanceWidgetBinding get instance =>
      BindingBase.checkInstance(_instance);
  static GlanceWidgetBinding? _instance;

  /// Initialize the [GlanceWidgetBinding]
  static GlanceWidgetBinding ensureInitialized() {
    if (GlanceWidgetBinding._instance == null) {
      GlanceWidgetBinding._();
    }
    return GlanceWidgetBinding.instance;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }
}

/// Defines a reporter that can report specific information in [Glance].
abstract class GlanceReporter<T> {
  void report(T info);
}

/// A reporter specifically for reporting UI jank infomations.
abstract class JankDetectedReporter extends GlanceReporter<JankReport> {}

/// A report containing information about detected jank. Currently, it only includes
/// the stack trace when UI jank occurs.
class JankReport {
  const JankReport({
    required this.stackTrace,
  });

  /// The stack traces captured when UI jank was detected.
  final StackTrace stackTrace;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is JankReport && stackTrace == other.stackTrace;
  }

  @override
  int get hashCode => stackTrace.hashCode;
}

/// Configuration class for [Glance]
class GlanceConfiguration {
  const GlanceConfiguration({
    this.jankThreshold = kDefaultJankThreshold,
    this.reporters = const [],
    List<String> modulePathFilters = const [],
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
  }) : _modulePathFilters = modulePathFilters;

  /// The threshold in milliseconds for detecting UI jank. Defaults to [kDefaultJankThreshold].
  final int jankThreshold;

  /// A list of reporters that will handle the reporting of UI jank.
  final List<GlanceReporter> reporters;

  /// Filters with regex patterns for module paths.
  /// If not set, [kAndroidDefaultModulePathFilters] is used on Android, and [kIOSDefaultModulePathFilters] is used on iOS.
  final List<String> _modulePathFilters;
  List<String> get modulePathFilters {
    if (_modulePathFilters.isNotEmpty) {
      return _modulePathFilters;
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? kAndroidDefaultModulePathFilters
        : kIOSDefaultModulePathFilters;
  }

  /// The interval in milliseconds for capture the stack traces. Defaults to [kDefaultSampleRateInMilliseconds].
  /// Lower value will capture more accuracy stack traces, but will impace the performance.
  final int sampleRateInMilliseconds;
}

/// The [Glance] is a singleton class for handling the monitoring functionality of UI jank detection.
/// Call [GlanceWidgetBinding.ensureInitialized] before using [Glance].
///
/// Implement your own [JankDetectedReporter] to receive the [JankReport].
/// After obtaining the [JankReport.stackTrace], you can symbolize it using the `flutter symbolize` command.
/// For more details, see https://docs.flutter.dev/deployment/obfuscate#read-an-obfuscated-stack-trace.
/// You can save the stack traces to files or upload them to your server and symbolize them later.
abstract class Glance {
  Glance._();

  static Glance? _instance;
  static Glance get instance {
    _instance ??= GlanceImpl();
    return _instance!;
  }

  /// Starts monitoring UI jank with the given configuration.
  /// If no configuration is provided, the default configuration is used.
  Future<void> start(
      {GlanceConfiguration config = const GlanceConfiguration()});

  /// Ends the Glance monitoring.
  Future<void> end();
}
