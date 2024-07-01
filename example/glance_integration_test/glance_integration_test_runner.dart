import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';

import '_test_runner.dart';

void main() {
  const processManager = LocalProcessManager();
  const file.FileSystem fileSystem = LocalFileSystem();
  runTest(processManager, fileSystem, [
    TestCase(
      description: 'vsync phase jank',
      testFilePath: 'glance_integration_test/vsync_phase_jank_test.dart',
      onCheckStackTrace: (stackTrace) async {
           // VsyncPhaseJankWidgetState._incrementCounter                   /Users/littlegnal/codes/personal-project/glance_plugin/glance/example/integration_test/glance_integration_test_main.dart:99:3     76
        // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10                                                                                 65
        // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10
        if (stackTrace.contains('VsyncPhaseJankWidgetState._incrementCounter') &&
            stackTrace.contains('jsonEncode')) {
          // success
          print('Test passed!');
          return true;
        } else {
          print('Test failed!');
        }
        return false;
      },
    ),
    TestCase(
      description: 'build phase jank',
      testFilePath: 'glance_integration_test/build_phase_jank_test.dart',
      onCheckStackTrace: (stackTrace) async {
        return true;
      },
    )
  ]);
}
