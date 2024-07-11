import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:process/process.dart';
import 'package:file/memory.dart';

import '../../bin/symbolize.dart';

class FakeProcessManager implements ProcessManager {
  ProcessResult processResult = ProcessResult(1, 0, '', '');

  @override
  bool canRun(executable, {String? workingDirectory}) {
    return true;
  }

  @override
  bool killPid(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    return true;
  }

  @override
  Future<ProcessResult> run(List<Object> command,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) {
    return Future.value(processResult);
  }

  @override
  ProcessResult runSync(List<Object> command,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) {
    return processResult;
  }

  @override
  Future<Process> start(List<Object> command,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      ProcessStartMode mode = ProcessStartMode.normal}) {
    throw UnimplementedError();
  }
}

void main() {
  test('symbolize', () {
    final processManager = FakeProcessManager();
    final fileSystem = MemoryFileSystem();
    final symbolFilePath = '';
    final stackTraceFilePath = '';
    final outputFilePath = '';
    symbolize(fileSystem, processManager, symbolFilePath, stackTraceFilePath,
        outputFilePath);

    final outputContent = fileSystem.file(outputFilePath).readAsStringSync();

    final expectedOutput = '';
    expect(expectedOutput, outputContent);
  });
}
