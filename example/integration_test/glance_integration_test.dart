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

void main() {
  const processManager = LocalProcessManager();
  const file.FileSystem fileSystem = LocalFileSystem();
  _run(processManager, fileSystem);
}

Future<void> _run(
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
      .listen((line) async {
    print(line);
    if (line.trim() == '[glance_test_finished]') {
      const file.FileSystem fileSystem = LocalFileSystem();
      const processManager = LocalProcessManager();
      final result = await _desymbols(
          fileSystem, processManager, '', collectedStackTraces.join('\n'));
      print('result: ');
      print(result);
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
