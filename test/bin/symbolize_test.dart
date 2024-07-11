import 'dart:convert';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:process/process.dart';
import 'package:file/memory.dart';

import '../../bin/symbolize.dart';

class FakeProcessManager implements ProcessManager {
  Map<String, ProcessResult> pcResultMap = {};

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
    throw UnimplementedError();
  }

  @override
  ProcessResult runSync(List<Object> command,
      {String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false,
      Encoding? stdoutEncoding = systemEncoding,
      Encoding? stderrEncoding = systemEncoding}) {
    final pc = command.last.toString();
    return pcResultMap[pc]!;
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
    const symbolFilePath = 'debug-info/app.android-arm64.symbols';
    const stackTraceFilePath = 'stack_traces.txt';

    fileSystem.file(stackTraceFilePath).writeAsStringSync('''
#0   540641718272 540642472608 libapp.so
#1   540641718272 540642472607 libapp.so
''');

    const outputFilePath = 'out_stack_traces.txt';

    final pcResult540642472608 = ProcessResult(
      1,
      0,
      '_MyHomePageState._incrementCounter\n/glance/example/lib/main.dart:116:3',
      '',
    );
    final pcResult540642472607 = ProcessResult(
      1,
      0,
      'jsonEncode\nthird_party/dart/sdk/lib/convert/json.dart:114:10',
      '',
    );
    processManager.pcResultMap = {
      '540642472608': pcResult540642472608,
      '540642472607': pcResult540642472607,
    };

    symbolize(fileSystem, processManager, symbolFilePath, stackTraceFilePath,
        outputFilePath);

    final outputContent = fileSystem.file(outputFilePath).readAsStringSync();

    // Beaware that there're extra 2 whitespaces at the end of the line
    const expectedOutput = '''
#0    _MyHomePageState._incrementCounter  /glance/example/lib/main.dart:116:3                
#1    jsonEncode                          third_party/dart/sdk/lib/convert/json.dart:114:10  
''';
    expect(outputContent, expectedOutput);
  });
}
