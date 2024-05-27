import 'package:args/args.dart';
import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';

import '_test_runner.dart';
import 'package:glance/src/logger.dart';

/// The `flutter test` command with `--split-debug-info` does not work in Flutter
/// integration tests with profile mode. Therefore, we parse the console output line by line
/// to handle our test process.
///
/// To add a new test case, add a new [TestCase] with the necessary
/// properties in `runTest`.
///
/// On iOS, you need to install the `libimobiledevice` tool first:
/// `brew install libimobiledevice`
/// `brew install ideviceinstaller`
void main(List<String> arguments) {
  final parser = ArgParser();
  parser.addOption(
    'run-on',
    allowed: ['ios', 'android'],
    help: 'The platform we want to run on.',
  );

  final results = parser.parse(arguments);
  final runOn = results.option('run-on');

  const processManager = LocalProcessManager();
  const file.FileSystem fileSystem = LocalFileSystem();
  runTest(
    processManager,
    fileSystem,
    [
      TestCase(
        description: 'vsync phase jank',
        testFilePath: 'glance_integration_test/touch_event_jank_test.dart',
        onCheckStackTrace: (stackTrace) async {
          final incrementFuncRegx = RegExp(
              r'(.*)TouchEventJankWidgetState._incrementCounter(.*)\/glance_integration_test/touch_event_jank_test.dart');

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
              r'(.*)expensiveFunction(.*)\/glance_integration_test/jank_app.dart');

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
    ],
    runOn: runOn == 'android' ? RunOnPlatform.android : RunOnPlatform.ios,
  );
}
