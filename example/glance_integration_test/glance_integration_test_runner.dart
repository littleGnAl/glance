import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';

import '_test_runner.dart';
import 'package:glance/src/logger.dart';

/// The flutter test with --spilt-debug-info not work in flutter integration test with
/// profile mode, so we parse the console output line by line to handle our test
/// process.
/// 
/// To add a new test case, you need to add a new [TestCase] with some necessary
/// proerpty in `runTest`.
void main() {
  const processManager = LocalProcessManager();
  const file.FileSystem fileSystem = LocalFileSystem();
  runTest(processManager, fileSystem, [
    TestCase(
      description: 'vsync phase jank',
      testFilePath: 'glance_integration_test/vsync_phase_jank_test.dart',
      onCheckStackTrace: (stackTrace) async {
        final incrementFuncRegx = RegExp(
            r'(.*)VsyncPhaseJankWidgetState._incrementCounter(.*)\/glance_integration_test/vsync_phase_jank_test.dart');

        if (incrementFuncRegx.hasMatch(stackTrace)) {
          // success
          GlanceLogger.log('Test passed!', prefixTag: false);
          return true;
        } else {
          GlanceLogger.log('Test failed!', prefixTag: false);
        }
        return false;
      },
    ),
    TestCase(
      description: 'build phase jank',
      testFilePath: 'glance_integration_test/build_phase_jank_test.dart',
      onCheckStackTrace: (stackTrace) async {
        final expensiveFuncRegx = RegExp(
            r'(.*)_BuildPhaseJankWidgetState._expensiveFunction(.*)\/glance_integration_test/build_phase_jank_test.dart');

        if (expensiveFuncRegx.hasMatch(stackTrace)) {
          // success
          GlanceLogger.log('Test passed!', prefixTag: false);
          return true;
        } else {
          GlanceLogger.log('Test failed!', prefixTag: false);
        }
        return false;
      },
    )
  ]);
}
