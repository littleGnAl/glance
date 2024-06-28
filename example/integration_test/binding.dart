import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:integration_test/integration_test.dart';

class GlanceIntegrationTestWidgetsFlutterBinding
    extends IntegrationTestWidgetsFlutterBinding {
  GlanceIntegrationTestWidgetsFlutterBinding._() : super();

  static GlanceIntegrationTestWidgetsFlutterBinding get instance =>
      BindingBase.checkInstance(_instance);
  static GlanceIntegrationTestWidgetsFlutterBinding? _instance;

  int beginFrameTimeInMillis_ = 0;

  static GlanceIntegrationTestWidgetsFlutterBinding ensureInitialized() {
    if (GlanceIntegrationTestWidgetsFlutterBinding._instance == null) {
      GlanceIntegrationTestWidgetsFlutterBinding._();
    }
    return GlanceIntegrationTestWidgetsFlutterBinding.instance;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }

  //   Future<List<int>> takeScreenshot(String screenshotName, [Map<String, Object?>? args]) async {
  //   reportData ??= <String, dynamic>{};
  //   reportData!['screenshots'] ??= <dynamic>[];
  //   final Map<String, dynamic> data = await callbackManager.takeScreenshot(screenshotName, args);
  //   assert(data.containsKey('bytes'));

  //   (reportData!['screenshots']! as List<dynamic>).add(data);
  //   return data['bytes']! as List<int>;
  // }

  Future<void> checkStackTrace(String name, String stackTrace) async {
    reportData ??= <String, dynamic>{};
    reportData!['glaceStackTraces'] ??= <dynamic>[];
    reportData!['glaceStackTraces']!.add({
      'stackTraceName': name,
      'glaceStackTrace': stackTrace,
    });
  }
}
