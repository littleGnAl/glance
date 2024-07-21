import 'dart:async';
import 'dart:convert';

import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import '../../bin/symbolize.dart';
import 'package:glance/src/logger.dart';

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

const _kCollectStackTracesStartFlag =
    '[glance_test] Collect stack traces start';
const _kCollectStackTracesEndFlag = '[glance_test] Collect stack traces end';
const _kGlanceTestStartedFlag = '[glance_test_started]';
const _kGlanceTestFinishedFlag = '[glance_test_finished]';

Future<String> _symbolize(
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
  GlanceLogger.log(
      'Running TestCase(${testCase.description}, ${testCase.testFilePath}) ...',
      prefixTag: false);
  GlanceLogger.log('Building ${testCase.testFilePath} ...', prefixTag: false);
  final buildDir = fileSystem.directory('build');
  if ((await buildDir.exists())) {
    await fileSystem.directory('build').delete(recursive: true);
  }

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

  bool isCollectingStackTraces = false;
  List<String> collectedStackTraces = [];
  bool isCheckStackTracesSuccess = false;
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) async {
    GlanceLogger.log(l, prefixTag: false);
  });
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) async {
    final line = l.replaceAll(RegExp(r'I\/flutter \((.*\d+)\): '), '');
    GlanceLogger.log(line, prefixTag: false);
    if (line.trim() == _kGlanceTestFinishedFlag) {
      const file.FileSystem fileSystem = LocalFileSystem();
      const processManager = LocalProcessManager();
      GlanceLogger.log('Symbolizing ...', prefixTag: false);
      final result = await _symbolize(
          fileSystem,
          processManager,
          path.basename(testCase.testFilePath),
          collectedStackTraces.join('\n'));

      GlanceLogger.log('Symbolized stack traces:', prefixTag: false);
      GlanceLogger.log(result, prefixTag: false);

      GlanceLogger.log('Checking stack trace ...', prefixTag: false);
      isCheckStackTracesSuccess = await testCase.onCheckStackTrace(result);

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

    if (line.trim() == _kCollectStackTracesStartFlag) {
      isCollectingStackTraces = true;
      stdout.writeln('Start collecting stack traces ...');
    }
    if (line.trim() == _kCollectStackTracesEndFlag) {
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
      GlanceLogger.log('Test case success: ${testCase.testFilePath}',
          prefixTag: false);
    } else {
      GlanceLogger.log('Test case failed: ${testCase.testFilePath}',
          prefixTag: false);
    }
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
