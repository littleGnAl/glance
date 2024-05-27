import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';
import 'package:glance/glance_platform_interface.dart';
import 'package:glance/glance_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockGlancePlatform
//     with MockPlatformInterfaceMixin
//     implements GlancePlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

void main() {
  final GlancePlatform initialPlatform = GlancePlatform.instance;

  test('test add', () {
    User().add();
  });

  // test('getPlatformVersion', () async {
  //   Glance glancePlugin = Glance();
  //   MockGlancePlatform fakePlatform = MockGlancePlatform();
  //   GlancePlatform.instance = fakePlatform;

  //   expect(await glancePlugin.getPlatformVersion(), '42');
  // });
}
