import 'package:flutter_test/flutter_test.dart';
import 'package:glance/glance.dart';
import 'package:glance/glance_platform_interface.dart';
import 'package:glance/glance_method_channel.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:glance/src/sampler.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// class MockGlancePlatform
//     with MockPlatformInterfaceMixin
//     implements GlancePlatform {

//   @override
//   Future<String?> getPlatformVersion() => Future.value('42');
// }

class FakeSampler implements Sampler {
  @override
  void close() {}

  @override
  Future<List<AggregatedNativeFrame>> getSamples(
      List<int> timestampRange) async {
    return [];
  }
}

void main() {
  late Glance glance;
  setUp(() {
    glance = GlanceImpl.forTesting(FakeSampler());
  });
  test('start then get a report', () {
    glance.start();
  });

  test('end', () {});

  // test('getPlatformVersion', () async {
  //   Glance glancePlugin = Glance();
  //   MockGlancePlatform fakePlatform = MockGlancePlatform();
  //   GlancePlatform.instance = fakePlatform;

  //   expect(await glancePlugin.getPlatformVersion(), '42');
  // });
}
