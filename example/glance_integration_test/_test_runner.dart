import 'dart:async';
import 'dart:convert';

import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import '../../bin/symbolize.dart';

typedef CheckStackTraceCallback = Future<bool> Function(String stackTrace);

class TestCase {
  TestCase(
      {required this.description,
      required this.testFilePath,
      required this.onCheckStackTrace});
  final String description;

  final String testFilePath;
  final CheckStackTraceCallback onCheckStackTrace;
}

Future<String> _desymbols(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String stackTraceFileName,
  String stackTrace,
) async {
  final symbolFilePath =
      path.join('debug-info-integration', 'app.android-arm64.symbols');
  final tmpFilePath = path.join(path.current, 'build',
      'glance_integration_test', '$stackTraceFileName.tmp');
  final tmpFile = fileSystem.file(tmpFilePath);
  await tmpFile.create(recursive: true);
  await tmpFile.writeAsString(stackTrace);

  String result =
      llmSymbolizer(fileSystem, processManager, symbolFilePath, tmpFilePath);
  return result;
}

Future<bool> _runTestCase(ProcessManager processManager,
    file.FileSystem fileSystem, TestCase testCase) async {
  print('Running ${testCase.description} ...');
  print('Building ${testCase.testFilePath} ...');
  await fileSystem.directory('build').delete(recursive: true);
  final processResult = await processManager.run([
    'flutter',
    'build',
    'apk',
    '--release',
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
    '--release',
    '--no-build',
    '--use-application-binary=build/app/outputs/flutter-apk/app-release.apk',
  ]);
  stdout.writeln('Running app...');

  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {});

  bool isCollectingStackTraces = false;
  List<String> collectedStackTraces = [];
  bool isCheckStackTracesSuccess = false;
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) async {
    final line = l.replaceAll(RegExp(r'I\/flutter \((.*\d+)\): '), '');
    print(line);
    if (line.trim() == '[glance_test_finished]') {
      const file.FileSystem fileSystem = LocalFileSystem();
      const processManager = LocalProcessManager();
      print('Desymboling ...');
      final result = await _desymbols(
          fileSystem,
          processManager,
          path.basename(testCase.testFilePath),
          collectedStackTraces.join('\n'));

      print('Checking stack trace ...');
      isCheckStackTracesSuccess = await testCase.onCheckStackTrace(result);

      // // VsyncPhaseJankWidgetState._incrementCounter                   /Users/littlegnal/codes/personal-project/glance_plugin/glance/example/integration_test/glance_integration_test_main.dart:99:3     76
      // // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10                                                                                 65
      // // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10
      // if (success) {
      //   // success
      //   print('Test passed!');
      // } else {
      //   print('Test failed!');
      // }

      // adb shell pm uninstall -k <package-name>
      // Uninsntall the package to restore to a clean state
      {
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

      process.kill();

      return;
    }

    if (line.trim() == '[glance_test] Collect stack traces start') {
      isCollectingStackTraces = true;
      stdout.writeln('Start collecting stack traces ...');
    }
    if (line.trim() == '[glance_test] Collect stack traces end') {
      isCollectingStackTraces = false;
      stdout.writeln('Collected stack traces');
    }

    if (isCollectingStackTraces) {
      collectedStackTraces.add(line);
    }
  });
  await process.exitCode;
  return isCheckStackTracesSuccess;
}

Future<void> runTest(
  ProcessManager processManager,
  file.FileSystem fileSystem,
  List<TestCase> testCases,
) async {
  for (final testCase in testCases) {
    final success = await _runTestCase(processManager, fileSystem, testCase);
    if (success) {
      print('Test case success: ${testCase.testFilePath}');
    } else {
      print('Test case failed: ${testCase.testFilePath}');
    }
  }
}

void checkStackTraces(String stackTraces) {
  print('[glance_test] Collect stack traces start');
  // The `print` will truncate the log, so we spilt the stack traces and `print` it
  // line by line to ensure the full stack traces
  stackTraces.split('\n').forEach((e) {
    print(e);
  });
  print('[glance_test] Collect stack traces end');
}

void glanceIntegrationTest(FutureOr<void> Function() callback) async {
  print('[glance_test_started]');
  await callback();
  print('[glance_test_finished]');
}
