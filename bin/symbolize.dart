import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:path/path.dart' as path;
import 'package:process/process.dart';

void main(List<String> arguments) {
  const file.FileSystem fileSystem = LocalFileSystem();
  final processManager = const LocalProcessManager();
  _symbolize(fileSystem, processManager, '', '');
}

/// pc: 0xab333
/// Frame(pc: 3396957692, module: Module(path: /data/app/com.example.thread_collect_stack_example-TBzzwMgiQJ7BUep7husHbA==/lib/arm/libapp.so, baseAddress: 3396415488))
/// backtrace:
///  #00  pc 0000000000042f89  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)
///  #01  pc 0000000000000640  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::runCrashThread())
///  #02  pc 0000000000065a3b  /system/lib/libc.so (__pthread_start(void*))
///  #03  pc 000000000001e4fd  /system/lib/libc.so (__start_thread)
///
/// [
///   {
///     "pc": "0000000000042f89",
///     "baseAddress": "3396415488",
///     "path": "/data/app/com.example.thread_collect_stack_example-TBzzwMgiQJ7BUep7husHbA==/lib/arm/libapp.so"
///   }
/// ]
void _symbolize(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String symbolFilePath,
  String stackTraceFilePath,
) {
  final stackTrackFile = fileSystem.file(stackTraceFilePath);
  final stackTrackFileContent = stackTrackFile.readAsStringSync();
  final stackTraceJson = jsonDecode(stackTrackFileContent);

  final frames = List.from(stackTraceJson).map((e) {
    final baseAddress = e['baseAddress'];
    final path = e['path'];
    final pc = e['pc'];
    NativeModule? module;
    if (baseAddress != null && path != null) {
      module = NativeModule(
        id: 0,
        path: path,
        baseAddress: baseAddress,
        symbolName: '',
      );
    }
    return NativeFrame(pc: pc, module: module);
  });

  for (final frame in frames) {
    if (frame.module != null) {
      // $ llvm-symbolizer --exe debug-info/app.android-arm.symbols --adjust-vma 3396415488 3396957692 3396957536 3397044152 3397056056 3397112352 3396903540 3397112352 3397057696 3397111684 3396845236 3396662844
      final cmd = [
        'llvm-symbolizer',
        '--exe',
        stackTraceFilePath,
        '--adjust-vma',
        frame.module!.baseAddress,
        frame.pc,
      ];
      final result = processManager.runSync(cmd);
      stdout.writeln(result.stdout);
    }
  }
}
