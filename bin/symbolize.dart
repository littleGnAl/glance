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

/// Symbolize using `llvm-symbolizer` cmd
/// llvm-symbolizer --exe debug-info/app.android-arm.symbols --adjust-vma <baseAddress> <pcs>
String llmSymbolizer(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String symbolFilePath,
  String stackTraceFilePath,
) {
  final stackTrackFile = fileSystem.file(stackTraceFilePath);
  final lines = stackTrackFile.readAsLinesSync();
  final stackTraceLineRegx = RegExp(r'^#[0-9]+\s*[0-9]+\s[0-9]+\s(.*)');
  final List<String> processLines = lines
      .where((line) => stackTraceLineRegx.hasMatch(line))
      .toList(growable: false);

  int maxFunctionNameLen = 0;
  int maxUriLen = 0;

  final List<_Holder> holders = [];
  for (final line in processLines) {
    late String baseAddress;
    late String pc;
    int subStart = 0;

    int processIndex = 0;
    int len = line.length;
    while (subStart < len) {
      while (subStart < len && line[subStart] == kGlanceStackTraceLineSpilt) {
        subStart++;
      }
      int subEnd = subStart;
      while (subEnd < len && line[subEnd] != kGlanceStackTraceLineSpilt) {
        subEnd++;
      }

      final value = line.substring(subStart, subEnd);
      // e.g.,
      // #0   540641718272 540642472608 libapp.so
      if (processIndex == 1) {
        baseAddress = value;
      } else if (processIndex == 2) {
        pc = value;
      }

      ++processIndex;
      subStart = subEnd;
      ++subStart;
    }

    // $ llvm-symbolizer --exe debug-info/app.android-arm.symbols --adjust-vma <baseAddress> <pcs>
    final cmd = [
      'llvm-symbolizer',
      '--exe',
      symbolFilePath,
      '--adjust-vma',
      baseAddress,
      pc,
    ];
    final result = processManager.runSync(cmd);
    String outString = result.stdout;
    String funcName = '';
    String uri = '';

    final outStringList =
        outString.split('\n').where((e) => e.isNotEmpty).toList();
    if (outStringList.length > 2) {
      for (int i = 0; i < outStringList.length; i += 2) {
        funcName = outStringList[0];
        uri = outStringList[1];
        holders.add(_Holder(
          baseAddr: baseAddress,
          pc: pc,
          funcName: funcName,
          uri: uri,
        ));

        maxFunctionNameLen = max(maxFunctionNameLen, funcName.length);
        maxUriLen = max(maxUriLen, uri.length);
      }
    } else {
      funcName = outStringList[0];
      uri = outStringList[1];
      holders.add(_Holder(
        baseAddr: baseAddress,
        pc: pc,
        funcName: funcName,
        uri: uri,
      ));

      maxFunctionNameLen = max(maxFunctionNameLen, funcName.length);
      maxUriLen = max(maxUriLen, uri.length);
    }
  }

  final stringBuffer = StringBuffer();
  int index = 0;
  for (final holder in holders) {
    stringBuffer.write('#');
    stringBuffer.write(index.toString().padRight(_adjustLen(3)));
    stringBuffer
        .write(holder.funcName.padRight(_adjustLen(maxFunctionNameLen)));
    stringBuffer.write(holder.uri.padRight(_adjustLen(maxUriLen)));
    stringBuffer.writeln(); // new line at the end
    ++index;
  }

  return stringBuffer.toString();
}

class _Holder {
  _Holder({
    required this.baseAddr,
    required this.pc,
    required this.funcName,
    required this.uri,
  });
  final String baseAddr;
  final String pc;
  final String funcName;
  final String uri;
}

/// Add extra 2 padding to make the string pretty
int _adjustLen(int len) {
  return len + 2;
}
