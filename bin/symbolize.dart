import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:path/path.dart' as path;
import 'package:process/process.dart';

void main(List<String> arguments) {
  final parser = ArgParser();
  parser.addOption('symbol-file', help: 'The symbol file path');
  parser.addOption('stack-trace-file', help: 'The stack trace file path');

  final results = parser.parse(arguments);
  final symbolFile = results.option('symbol-file');
  final stackTraceFile = results.option('stack-trace-file');

  const file.FileSystem fileSystem = LocalFileSystem();
  const processManager = LocalProcessManager();
  _symbolize(fileSystem, processManager, symbolFile!, stackTraceFile!);
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

  final frames = List.from(stackTraceJson['stackTraces']).map((e) {
    final baseAddress = e['baseAddress'];
    final path = e['path'];
    final pc = e['pc'];
    final ts = e['timestamp'];
    final spent = e['spent'] ?? 0;
    NativeModule? module;
    if (baseAddress != null && path != null) {
      module = NativeModule(
        id: 0,
        path: path,
        baseAddress: int.parse(baseAddress),
        symbolName: '',
      );
    }
    final nativeFrame =
        NativeFrame(pc: int.parse(pc), module: module, timestamp: ts);
    return NativeFrameTimeSpent(nativeFrame)..timestampInMacros = spent;
  });

  // base_addr pc functions uri times

  int maxBaseAddrLen = 0;
  int maxPCLen = 0;
  int maxFunctionNameLen = 0;
  int maxUriLen = 0;
  int maxTimesLen = 0;

  // for (final f in frames) {
  //   final frame = f.frame;
  //   if (frame.module != null) {
  //     maxBaseAddrLen =
  //         max(maxTimesLen, frame.module!.baseAddress.toString().length);
  //     maxPCLen = max(maxPCLen, frame.pc.toString().length);
  //     // maxFunctionNameLen = max(frame.);
  //   }
  // }

  final List<_Holder> holders = [];
  for (final f in frames) {
    final frame = f.frame;
    if (frame.module != null) {
      // $ llvm-symbolizer --exe debug-info/app.android-arm.symbols --adjust-vma 3396415488 3396957692 3396957536 3397044152 3397056056 3397112352 3396903540 3397112352 3397057696 3397111684 3396845236 3396662844
      final cmd = [
        'llvm-symbolizer',
        '--exe',
        symbolFilePath,
        '--adjust-vma',
        frame.module!.baseAddress,
        frame.pc,
      ];
      final result = processManager.runSync(cmd);
      // stdout.writeln(
      //     'frame.module!.baseAddress: ${frame.module!.baseAddress} frame.pc: ${frame.pc}, frame.module!.path: ${frame.module!.path}, spent: ${f.timestampInMacros}');
      String outString = result.stdout;
      // outString = outString.split('\n').where((e) => e.isNotEmpty); //.join('##');
      // stdout.writeln(outString);

      // third_party/dart/sdk/lib/convert/json.dart:114:10##
      final uriRegx = RegExp(r'(.+)*\/\.dart\:\d+\:\d+');

      final baseAddress = frame.module!.baseAddress.toString();
      final pc = frame.pc.toString();
      String funcName = '';
      String uri = '';
      String spent = f.timestampInMacros.toString();

      maxBaseAddrLen = max(maxTimesLen, baseAddress.length);
      maxPCLen = max(maxPCLen, pc.length);
      maxTimesLen = max(maxTimesLen, spent.length);

      final outStringList =
          outString.split('\n').where((e) => e.isNotEmpty).toList();
      if (outStringList.length > 2) {
        for (int i = 0; i < outStringList.length; i += 2) {
          funcName = outStringList[0];
          assert(uriRegx.hasMatch(uri));
          uri = outStringList[1];
          holders.add(_Holder(
            baseAddr: baseAddress,
            pc: pc,
            funcName: funcName,
            uri: uri,
            times: spent,
          ));

          maxFunctionNameLen = max(maxFunctionNameLen, funcName.length);
          maxUriLen = max(maxUriLen, uri.length);
        }
      } else {
        funcName = outStringList[0];
        assert(uriRegx.hasMatch(uri));
        uri = outStringList[1];
        holders.add(_Holder(
          baseAddr: baseAddress,
          pc: pc,
          funcName: funcName,
          uri: uri,
          times: spent,
        ));

        maxFunctionNameLen = max(maxFunctionNameLen, funcName.length);
        maxUriLen = max(maxUriLen, uri.length);
      }

      // stdout.writeln();
    }
  }

  final sb = StringBuffer();
  // // base_addr pc functions uri times
  // sb.write('base_addr'.padRight(_adjustLen(maxBaseAddrLen)));
  // sb.write('pc'.padRight(_adjustLen(maxPCLen)));
  sb.write('functions'.padRight(_adjustLen(maxFunctionNameLen)));
  sb.write('uri'.padRight(_adjustLen(maxUriLen)));
  sb.write('times'.padRight(_adjustLen(maxTimesLen)));
  sb.writeln(); // new line
  for (final holder in holders) {
    // sb.write(holder.baseAddr.padRight(_adjustLen(maxBaseAddrLen)));
    // sb.write(holder.pc.padRight(_adjustLen(maxPCLen)));
    sb.write(holder.funcName.padRight(_adjustLen(maxFunctionNameLen)));
    sb.write(holder.uri.padRight(_adjustLen(maxUriLen)));
    sb.write(holder.times.padRight(_adjustLen(maxTimesLen)));
    sb.writeln(); // new line
  }

  stdout.writeln(sb.toString());
}

class _Holder {
  _Holder({
    required this.baseAddr,
    required this.pc,
    required this.funcName,
    required this.uri,
    required this.times,
  });
  final String baseAddr;
  final String pc;
  final String funcName;
  final String uri;
  final String times;
}

/// Add extra 4 padding to make the string pretty
int _adjustLen(int len) {
  return len + 4;
}
