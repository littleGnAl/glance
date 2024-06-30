import 'dart:convert';

import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

import '../../bin/symbolize.dart';

Future<String> _desymbols(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String stackTraceFileName,
  String stackTrace,
) async {
  final symbolFilePath =
      path.join('debug-info-integration', 'app.android-arm64.symbols');
  final tmpFilePath = path.join(path.current, 'build',
      'glance_integration_test', '${stackTraceFileName}.tmp');
  // final outputDir = fileSystem.directory(outputDirPath);
  // if (out)
  final tmpFile = fileSystem.file(tmpFilePath);
  await tmpFile.create(recursive: true);
  await tmpFile.writeAsString(stackTrace);

  String result =
      symbolize(fileSystem, processManager, symbolFilePath!, tmpFilePath);
  return result;
}

Future<void> runTest(
  ProcessManager processManager,
  file.FileSystem fileSystem,
) async {
  stdout.writeln('Building app...');
  // example/integration_test/glance_integration_test_main.dart
  // flutter build apk --profile --split-debug-info=debug-info-integration --target integration_test/glance_integration_test_main.dart
  await processManager.run([
    'flutter',
    'build',
    'apk',
    '--release',
    '--split-debug-info=debug-info-integration',
    '--target=integration_test/glance_integration_test_main.dart',
  ]);
  stdout.writeln('Built app');

  stdout.writeln('Running app...');
// flutter run --no-build --use-application-binary=build/app/outputs/flutter-apk/app-profile.apk
  final process = await processManager.start([
    'flutter',
    'run',
    '--release',
    '--no-build',
    '--use-application-binary=build/app/outputs/flutter-apk/app-release.apk',
  ]);

  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {});

  bool isCollectingStackTraces = false;
  List<String> collectedStackTraces = [];
  // Process JSON-RPC events from the flutter run command.
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) async {
    final line = l.replaceAll(RegExp(r'I\/flutter \(\d+\): '), '');
    // print('line.trim(): ${line.trim()}');
    if (line.trim() == '[glance_test_finished]') {
      const file.FileSystem fileSystem = LocalFileSystem();
      const processManager = LocalProcessManager();
      final result = await _desymbols(
          fileSystem, processManager, '', collectedStackTraces.join('\n'));
      print('result: ');
      print(result);

      // VsyncPhaseJankWidgetState._incrementCounter                   /Users/littlegnal/codes/personal-project/glance_plugin/glance/example/integration_test/glance_integration_test_main.dart:99:3     76
      // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10                                                                                 65
      // jsonEncode                                                    third_party/dart/sdk/lib/convert/json.dart:114:10
      if (result.contains('VsyncPhaseJankWidgetState._incrementCounter') &&
          result.contains('jsonEncode')) {
        // success
        print('Test passed!');
      } else {
        print('Test failed!');
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
}