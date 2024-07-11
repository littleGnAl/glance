import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';
import 'package:glance/src/constants.dart';
import 'package:process/process.dart';

void main(List<String> arguments) {
  final parser = ArgParser();
  parser.addOption('symbol-file', help: 'The symbol file path');
  parser.addOption('stack-traces-file', help: 'The stack traces file path');
  parser.addOption('out', help: 'The de-symbol stack traces output file path');

  final results = parser.parse(arguments);
  final symbolFile = results.option('symbol-file');
  final stackTraceFile = results.option('stack-traces-file');
  final outputFile = results.option('out');

  const file.FileSystem fileSystem = LocalFileSystem();
  const processManager = LocalProcessManager();
  symbolize(
      fileSystem, processManager, symbolFile!, stackTraceFile!, outputFile!);
}

void symbolize(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String symbolFilePath,
  String stackTraceFilePath,
  String outputFilePath,
) {
  final out = llmSymbolizer(
      fileSystem, processManager, symbolFilePath, stackTraceFilePath);
  fileSystem.file(outputFilePath).writeAsStringSync(out);
}

/// pc: 0xab333
/// Frame(pc: 3396957692, module: Module(path: /data/app/com.example.thread_collect_stack_example-TBzzwMgiQJ7BUep7husHbA==/lib/arm/libapp.so, baseAddress: 3396415488))
/// backtrace:
///  #00  pc 0000000000042f89  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)
///  #01  pc 0000000000000640  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::runCrashThread())
///  #02  pc 0000000000065a3b  /system/lib/libc.so (__pthread_start(void*))
///  #03  pc 000000000001e4fd  /system/lib/libc.so (__start_thread)
///
///
/// base_addr: 0000000000000640
///   #00  pc 0000000000042f89  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::Crasher::crash() const)   ~30ms
///   #01  pc 0000000000000640  /data/app/com.example.testapp/lib/arm64/libexample.so (com::example::runCrashThread())         ~30ms
///   #02  pc 0000000000065a3b  /system/lib/libc.so (__pthread_start(void*))                                                   ~30ms
///   #03  pc 000000000001e4fd  /system/lib/libc.so (__start_thread)
///
/// [
///   {
///     "pc": "0000000000042f89",
///     "baseAddress": "3396415488",
///     "path": "/data/app/com.example.thread_collect_stack_example-TBzzwMgiQJ7BUep7husHbA==/lib/arm/libapp.so"
///   }
/// ]
String llmSymbolizer(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String symbolFilePath,
  String stackTraceFilePath,
) {
  final stackTrackFile = fileSystem.file(stackTraceFilePath);
  // final stackTrackFileContent = stackTrackFile.readAsStringSync();
  final lines = stackTrackFile.readAsLinesSync();
  final stackTraceLineRegx = RegExp(r'^#[0-9]+\s*[0-9]+\s[0-9]+\s(.*)');
  final List<String> processLines = lines
      .where((line) => stackTraceLineRegx.hasMatch(line))
      .toList(growable: false);
  // bool isFoundHeaderLine = false;

  // for (final line in lines) {
  //   if (line == kGlaceStackTraceHeaderLine) {
  //     continue;
  //   }
  //   if (!line.startsWith('#')) {
  //     continue;
  //   }

  //   // final spilted = line.split(glaceStackTraceLineSpilt);

  //   if (stackTraceLineRegx.hasMatch(line)) {
  //     processLines.add(line);
  //   }

  //   // final baseAddress =  e['baseAddress'];
  //   // final path = e['path'];
  //   // final pc = e['pc'];
  //   // final ts = e['timestamp'];
  //   // final spent = e['spent'] ?? 0;
  //   // NativeModule? module;
  //   // if (baseAddress != null && path != null) {
  //   //   module = NativeModule(
  //   //     id: 0,
  //   //     path: path,
  //   //     baseAddress: int.parse(baseAddress),
  //   //     symbolName: '',
  //   //   );
  //   // }
  //   // final nativeFrame =
  //   //     NativeFrame(pc: int.parse(pc), module: module, timestamp: ts);
  //   // return NativeFrameTimeSpent(nativeFrame)..timestampInMacros = spent;
  // }

  // final stackTraceJson = jsonDecode(stackTrackFileContent);

  // final frames = List.from(stackTraceJson['stackTraces']).map((e) {
  //   final baseAddress = e['baseAddress'];
  //   final path = e['path'];
  //   final pc = e['pc'];
  //   final ts = e['timestamp'];
  //   final spent = e['spent'] ?? 0;
  //   NativeModule? module;
  //   if (baseAddress != null && path != null) {
  //     module = NativeModule(
  //       id: 0,
  //       path: path,
  //       baseAddress: int.parse(baseAddress),
  //       symbolName: '',
  //     );
  //   }
  //   final nativeFrame =
  //       NativeFrame(pc: int.parse(pc), module: module, timestamp: ts);
  //   return NativeFrameTimeSpent(nativeFrame)..timestampInMacros = spent;
  // });

  // base_addr pc functions uri times

  // int maxBaseAddrLen = 0;
  // int maxPCLen = 0;
  int maxFunctionNameLen = 0;
  int maxUriLen = 0;
  // int maxTimesLen = 0;

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
  for (final line in processLines) {
    late String baseAddress;
    late String pc;
    int subStart = 0;
    int subEnd = 0;
    int processIndex = 0;
    while (subStart < line.length) {
      while (line[subStart++] == kGlaceStackTraceLineSpilt) {}
      while (line[subEnd++] != kGlaceStackTraceLineSpilt) {}

      final value = line.substring(subStart, subEnd);

      if (processIndex == 0) {
        baseAddress = value;
      } else if (processIndex == 1) {
        pc = value;
      }

      ++subStart;
    }

    // final splited = line.split(kGlaceStackTraceLineSpilt);
    // assert(splited.length == 5);
    // final baseAddress = splited[1];
    // final pc = splited[2];
    // final spent = splited[3];
    // final path = splited[4];

    // final frame = f.frame;
    // if (frame.module != null) {

    //   // stdout.writeln();
    // }

    // $ llvm-symbolizer --exe debug-info/app.android-arm.symbols --adjust-vma <baseAddress> <pcs>
    final cmd = [
      'llvm-symbolizer',
      '--exe',
      symbolFilePath,
      '--adjust-vma',
      // frame.module!.
      baseAddress,
      // frame.
      pc,
    ];
    final result = processManager.runSync(cmd);
    // stdout.writeln(
    //     'frame.module!.baseAddress: ${frame.module!.baseAddress} frame.pc: ${frame.pc}, frame.module!.path: ${frame.module!.path}, spent: ${f.timestampInMacros}');
    String outString = result.stdout;
    // outString = outString.split('\n').where((e) => e.isNotEmpty); //.join('##');
    // stdout.writeln(outString);

    // third_party/dart/sdk/lib/convert/json.dart:114:10##
    final uriRegx = RegExp(r'(.+)*\/\.dart\:\d+\:\d+');

    // final baseAddress = frame.module!.baseAddress.toString();
    // final pc = frame.pc.toString();
    String funcName = '';
    String uri = '';
    // String spent = f.timestampInMacros.toString();

    // maxBaseAddrLen = max(maxTimesLen, baseAddress.length);
    // maxPCLen = max(maxPCLen, pc.length);
    // maxTimesLen = max(maxTimesLen, spent.length);

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
          // times: spent,
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
        // times: spent,
      ));

      maxFunctionNameLen = max(maxFunctionNameLen, funcName.length);
      maxUriLen = max(maxUriLen, uri.length);
    }
  }

  final sb = StringBuffer();
  // // base_addr pc functions uri times
  // sb.write('base_addr'.padRight(_adjustLen(maxBaseAddrLen)));
  // sb.write('pc'.padRight(_adjustLen(maxPCLen)));
  // sb.write('functions'.padRight(_adjustLen(maxFunctionNameLen)));
  // sb.write('uri'.padRight(_adjustLen(maxUriLen)));
  // sb.write('times'.padRight(_adjustLen(maxTimesLen)));
  // sb.writeln(); // new line
  int index = 0;
  for (final holder in holders) {
    sb.write(index.toString().padRight(_adjustLen(3)));
    // sb.write(holder.baseAddr.padRight(_adjustLen(maxBaseAddrLen)));
    // sb.write(holder.pc.padRight(_adjustLen(maxPCLen)));
    sb.write(holder.funcName.padRight(_adjustLen(maxFunctionNameLen)));
    sb.write(holder.uri.padRight(_adjustLen(maxUriLen)));
    // sb.write(holder.times.padRight(_adjustLen(maxTimesLen)));
    sb.writeln(); // new line
    ++index;
  }

  // final out = sb.toString();

  // stdout.writeln(sb.toString());

  // fileSystem.file(outputFilePath).writeAsStringSync(sb.toString());

  // return out;
  return sb.toString();
}

class _Holder {
  _Holder({
    required this.baseAddr,
    required this.pc,
    required this.funcName,
    required this.uri,
    // required this.times,
  });
  final String baseAddr;
  final String pc;
  final String funcName;
  final String uri;
  // final String times;
}

/// Add extra 2 padding to make the string pretty
int _adjustLen(int len) {
  return len + 2;
}
