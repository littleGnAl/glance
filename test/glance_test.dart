import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';

void main() {
  group('GlanceConfiguration get modulePathFilters', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('has set modulePathFilters', () {
      const config = GlanceConfiguration(modulePathFilters: ['hello']);
      expect(config.modulePathFilters, equals(['hello']));
    });

    test('has not set modulePathFilters on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const config = GlanceConfiguration();
      expect(config.modulePathFilters, kAndroidDefaultModulePathFilters);
    });

    test('has not set modulePathFilters on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const config = GlanceConfiguration();
      expect(config.modulePathFilters, kIOSDefaultModulePathFilters);
    });
  });
}
