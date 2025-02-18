import 'dart:async';
import 'dart:convert';

import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import 'package:glance/src/logger.dart';

typedef CheckStackTraceCallback = Future<bool> Function(String stackTrace);

class TestCase {
  TestCase({
    required this.description,
    required this.testFilePath,
    required this.onCheckStackTrace,
  });
  final String description;

  final String testFilePath;
  final CheckStackTraceCallback onCheckStackTrace;
}

const _kCollectStackTracesStartFlag =
    '[glance_test] Collect stack traces start';
const _kCollectStackTracesEndFlag = '[glance_test] Collect stack traces end';
const _kGlanceTestStartedFlag = '[glance_test_started]';
const _kGlanceTestFinishedFlag = '[glance_test_finished]';

/// Calling this function requires `libimobiledevice` and `ideviceinstaller` to be installed.
/// Use the following commands to install them:
/// `brew install libimobiledevice`
/// `brew install ideviceinstaller`
Future<void> _uninstallIOSApp(
  file.FileSystem fileSystem,
  ProcessManager processManager,
) async {
  const appBundleId = 'com.littlegnal.glanceExample';
  String deviceUDId = '';

  // flutter symbolize -i <stack trace file> -d <symbol file> -o <out file>
  {
    final processResult = await processManager.run(['idevice_id', '-l']);
    if (processResult.exitCode != 0) {
      stderr.writeln(processResult.stderr);
    } else {
      deviceUDId = processResult.stdout.trim();
      GlanceLogger.log('Found device: $deviceUDId', prefixTag: false);
    }
  }

  {
    // ideviceinstaller -u <udid> --uninstall <bundle_id>
    final processResult = await processManager.run([
      'ideviceinstaller',
      '-u',
      deviceUDId,
      '--uninstall',
      '"$appBundleId"',
    ]);
    if (processResult.exitCode != 0) {
      stderr.writeln(processResult.stderr);
    } else {
      GlanceLogger.log(processResult.stdout.toString(), prefixTag: false);
    }
  }
}

Future<String> _symbolize(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String symbolFilePath,
  String stackTraceFileName,
  String stackTrace,
) async {
  final tmpStackTraceFilePath = path.join(
    path.current,
    'build',
    'glance_integration_test',
    '$stackTraceFileName.txt',
  );
  final tmpStackTraceFile = fileSystem.file(tmpStackTraceFilePath);
  await tmpStackTraceFile.create(recursive: true);
  await tmpStackTraceFile.writeAsString(stackTrace);

  final tmpStackTraceOutPath = path.join(
    path.current,
    'build',
    'glance_integration_test',
    'out_$stackTraceFileName.txt',
  );
  final tmpStackTraceOutFile = fileSystem.file(tmpStackTraceOutPath);
  await tmpStackTraceOutFile.create(recursive: true);

  // flutter symbolize -i <stack trace file> -d <symbol file> -o <out file>
  final processResult = await processManager.run([
    'flutter',
    'symbolize',
    '-i',
    tmpStackTraceFilePath,
    '-d',
    symbolFilePath,
    '-o',
    tmpStackTraceOutPath,
  ]);
  if (processResult.exitCode != 0) {
    stderr.writeln(processResult.stderr);
  }

  return tmpStackTraceOutFile.readAsStringSync();
}

Future<bool> _runTestCase(
  ProcessManager processManager,
  file.FileSystem fileSystem,
  RunOnPlatform runOn,
  TestCase testCase,
) async {
  GlanceLogger.log(
    'Running TestCase(${testCase.description}, ${testCase.testFilePath}) on ${runOn == RunOnPlatform.android ? 'Android' : 'iOS'} ...',
    prefixTag: false,
  );

  // Run `flutter clean` to get a clean build.
  await processManager.run(['flutter', 'clean']);
  GlanceLogger.log('Cleaned cache.', prefixTag: false);
  GlanceLogger.log('Building ${testCase.testFilePath} ...', prefixTag: false);

  if ((fileSystem.directory('debug-info-integration').existsSync())) {
    fileSystem.directory('debug-info-integration').deleteSync(recursive: true);
  }
  fileSystem.directory('debug-info-integration').createSync(recursive: true);

  final processResult = await processManager.run([
    'flutter',
    'build',
    if (runOn == RunOnPlatform.android) 'apk',
    if (runOn == RunOnPlatform.ios) 'ios',
    if (runOn == RunOnPlatform.android) '--release',
    if (runOn == RunOnPlatform.ios) '--profile',
    '--split-debug-info=debug-info-integration',
    '--target=${testCase.testFilePath}',
  ]);
  if (processResult.exitCode != 0) {
    stderr.writeln(processResult.stderr);
  }
  stdout.writeln('Built ${testCase.testFilePath}.');

  final process = await processManager.start([
    'flutter',
    'run',
    if (runOn == RunOnPlatform.android) '--release',
    if (runOn == RunOnPlatform.ios) '--profile',
    '--no-build',
    if (runOn == RunOnPlatform.android)
      '--use-application-binary=build/app/outputs/flutter-apk/app-release.apk',
    if (runOn == RunOnPlatform.ios)
      '--use-application-binary=build/ios/iphoneos/Runner.app',
  ]);
  stdout.writeln('Running app...');

  bool isCollectingStackTraces = false;
  List<String> collectedStackTraces = [];
  bool isCheckStackTracesSuccess = false;
  process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (l) async {
      GlanceLogger.log(l, prefixTag: false);
    },
  );
  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (l) async {
      final line =
          runOn == RunOnPlatform.android
              ? l.replaceAll(RegExp(r'I\/flutter \((.*\d+)\): '), '')
              : l.replaceAll(RegExp(r'flutter: '), '');
      GlanceLogger.log(line, prefixTag: false);
      if (line.trim() == _kCollectStackTracesEndFlag) {
        isCollectingStackTraces = false;
        stdout.writeln('Collected stack traces');

        const file.FileSystem fileSystem = LocalFileSystem();
        const processManager = LocalProcessManager();
        GlanceLogger.log('Symbolizing ...', prefixTag: false);

        final symbolFilePath =
            runOn == RunOnPlatform.android
                ? path.join(
                  'debug-info-integration',
                  'app.android-arm64.symbols',
                )
                : path.join('debug-info-integration', 'app.ios-arm64.symbols');

        final result = await _symbolize(
          fileSystem,
          processManager,
          symbolFilePath,
          path.basename(testCase.testFilePath),
          collectedStackTraces.join('\n'),
        );

        GlanceLogger.log('Symbolized stack traces:', prefixTag: false);
        GlanceLogger.log(result, prefixTag: false);

        GlanceLogger.log('Checking stack trace ...', prefixTag: false);
        isCheckStackTracesSuccess = await testCase.onCheckStackTrace(result);

        if (isCheckStackTracesSuccess) {
          if (runOn == RunOnPlatform.android) {
            // adb shell pm uninstall -k <package-name>
            // Uninsntall the package to restore to a clean state
            final processResult = await processManager.run([
              'adb',
              'shell',
              'pm',
              'uninstall',
              '-k',
              'com.littlegnal.glance_example',
            ]);
            if (processResult.exitCode != 0) {
              stderr.writeln(processResult.stderr);
            }
          }
          if (runOn == RunOnPlatform.ios) {
            await _uninstallIOSApp(fileSystem, processManager);
          }

          process.kill();
          return;
        }
      }

      if (line.trim() == _kCollectStackTracesStartFlag) {
        isCollectingStackTraces = true;
        stdout.writeln('Start collecting stack traces ...');
      }

      if (isCollectingStackTraces) {
        collectedStackTraces.add(line);
      }
    },
  );
  await process.exitCode;
  return isCheckStackTracesSuccess;
}

enum RunOnPlatform { ios, android }

Future<void> runTest(
  ProcessManager processManager,
  file.FileSystem fileSystem,
  List<TestCase> testCases, {
  RunOnPlatform runOn = RunOnPlatform.android,
}) async {
  List<TestCase> failedTestCases = [];
  for (final testCase in testCases) {
    final success = await _runTestCase(
      processManager,
      fileSystem,
      runOn,
      testCase,
    );
    if (success) {
      GlanceLogger.log(
        'Test case success: ${testCase.testFilePath}',
        prefixTag: false,
      );
    } else {
      GlanceLogger.log(
        'Test case failed: ${testCase.testFilePath}',
        prefixTag: false,
      );
      failedTestCases.add(testCase);
    }
  }

  if (failedTestCases.isNotEmpty) {
    GlanceLogger.log('Some test cases failed:', prefixTag: false);
    for (final e in failedTestCases) {
      GlanceLogger.log(
        '- "${e.description}", ${e.testFilePath}',
        prefixTag: false,
      );
    }
    exit(1);
  }
}

void checkStackTraces(String stackTraces) {
  GlanceLogger.log(_kCollectStackTracesStartFlag, prefixTag: false);
  // The `print` method will cause the output log to be truncated, so we spilt
  // the stack traces and `print` it line by line to ensure the full stack traces
  stackTraces.split('\n').forEach((e) {
    GlanceLogger.log(e, prefixTag: false);
  });
  GlanceLogger.log(_kCollectStackTracesEndFlag, prefixTag: false);
}

void glanceIntegrationTest(FutureOr<void> Function() callback) async {
  GlanceLogger.log(_kGlanceTestStartedFlag, prefixTag: false);
  await callback();
  GlanceLogger.log(_kGlanceTestFinishedFlag, prefixTag: false);
}
