import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Dl_info from dlfcn.h.
///
/// See `man dladdr`.
final class DlInfo extends ffi.Struct {
  external ffi.Pointer<Utf8> fileName;
  external ffi.Pointer<ffi.Void> baseAddress;
  external ffi.Pointer<Utf8> symbolName;
  external ffi.Pointer<ffi.Void> symbolAddress;
}

class NativeFrame {
  final NativeModule? module;
  final int pc;
  NativeFrame({this.module, required this.pc});
}

class NativeModule {
  final int id;
  final String path;
  final int baseAddress;
  final String symbolName;
  NativeModule(
      {required this.id,
      required this.path,
      required this.baseAddress,
      required this.symbolName});
}

class NativeStack {
  final List<NativeFrame> frames;
  final List<NativeModule> modules;
  NativeStack({required this.frames, required this.modules});
}

/// Bindings to IrisEventHandler
class NativeIrisEventBinding {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  NativeIrisEventBinding(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  NativeIrisEventBinding.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  void SetCurrentThreadAsTarget() {
    return _SetCurrentThreadAsTarget();
  }

  late final _SetCurrentThreadAsTargetPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function()>>(
          'SetCurrentThreadAsTarget');
  late final _SetCurrentThreadAsTarget =
      _SetCurrentThreadAsTargetPtr.asFunction<void Function()>();

  // @Native<Void Function()>(symbol: 'SetCurrentThreadAsTarget')
  // external void setCurrentThreadAsTarget();

  ffi.Pointer<Utf8> CollectStackTraceOfTargetThread(
    ffi.Pointer<ffi.Int64> buf,
    int bufSize,
  ) {
    return _CollectStackTraceOfTargetThread(buf, bufSize);
  }

  late final _CollectStackTraceOfTargetThreadPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Int64>,
              ffi.Size)>>('CollectStackTraceOfTargetThread');
  late final _CollectStackTraceOfTargetThread =
      _CollectStackTraceOfTargetThreadPtr.asFunction<
          ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Int64>, int)>();

  /// From collect_stack.cc
  // @Native<Pointer<Utf8> Function(Pointer<Int64>, Size)>(
  //     symbol: 'CollectStackTraceOfTargetThread')
  // external Pointer<Utf8> _collectStackTraceOfTargetThread(
  //     Pointer<Int64> buf, int bufSize);

  ffi.Pointer<ffi.Void> Dlopen(
    ffi.Pointer<Utf8> path,
    int flags,
  ) {
    return _Dlopen(path, flags);
  }

  late final _DlopenPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<Utf8>, ffi.Int)>>('dlopen');
  late final _Dlopen = _DlopenPtr.asFunction<
      ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, int)>();

  /// `void *dlopen(const char *filename, int flags);`
  ///
  /// See `man dlopen`
  // @Native<Pointer<Void> Function(Pointer<Utf8> path, Int)>(symbol: 'dlopen')
  // external Pointer<Void> _dlopen(Pointer<Utf8> path, int flags);

  // LookupSymbolName

  ffi.Pointer<Utf8> LookupSymbolName(
    ffi.Pointer<DlInfo> info,
  ) {
    return _LookupSymbolName(info);
  }

  late final _LookupSymbolNamePtr = _lookup<
          ffi.NativeFunction<ffi.Pointer<Utf8> Function(ffi.Pointer<DlInfo>)>>(
      'LookupSymbolName');
  late final _LookupSymbolName = _LookupSymbolNamePtr.asFunction<
      ffi.Pointer<Utf8> Function(ffi.Pointer<DlInfo>)>();

  int Dladdr(
    ffi.Pointer<ffi.Void> addr,
    ffi.Pointer<DlInfo> info,
  ) {
    return _dladdr(addr, info);
  }

  late final _dladdrPtr = _lookup<
      ffi.NativeFunction<
          ffi.Int Function(
              ffi.Pointer<ffi.Void>, ffi.Pointer<DlInfo>)>>('dladdr');
  late final _dladdr = _dladdrPtr
      .asFunction<int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<DlInfo>)>();

  /// `int dladdr(const void *addr, Dl_info *info);`
  ///
  /// See `man dladdr`
  // @Native<Int Function(Pointer<Void> addr, Pointer<DlInfo>)>(symbol: 'dladdr')
  // external int _dladdr(Pointer<Void> addr, Pointer<DlInfo> info);

  NativeStack captureStackOfTargetThread() {
    return using((arena) {
      // Invoke CollectStackTrace from helper library.
      const maxStackDepth = 1024;
      final outputBuffer =
          arena.allocate<ffi.Int64>(ffi.sizeOf<ffi.Int64>() * maxStackDepth);
      final error =
          CollectStackTraceOfTargetThread(outputBuffer, maxStackDepth);
      if (error != ffi.nullptr) {
        final errorString = error.toDartString();
        malloc.free(error);
        throw StateError(errorString); // Something went wrong.
      }

      final dlInfo = arena.allocate<DlInfo>(ffi.sizeOf<DlInfo>());

      // Process stack trace: which is a sequence of hexadecimal numbers
      // separated by commas. For each frame try to locate base address
      // of the module it belongs to using |dladdr|.
      final modules = <String, NativeModule>{};
      final frames = outputBuffer
          .asTypedList(maxStackDepth)
          .takeWhile((value) => value != 0)
          .map((addr) {
        final found = Dladdr(ffi.Pointer<ffi.Void>.fromAddress(addr), dlInfo);
        if (found == 0) {
          return NativeFrame(pc: addr);
        }

        if (dlInfo.ref.symbolName != ffi.nullptr) {
          print(
              'dlInfo.ref.symbolName: ${dlInfo.ref.symbolName.toDartString()}');
        }

        final sn = LookupSymbolName(dlInfo);
        if (sn != ffi.nullptr) {
          print('sn: ${sn.toDartString()}');
        }
        if (dlInfo.ref.fileName != ffi.nullptr) {
          print('dlInfo.ref.fileName: ${dlInfo.ref.fileName.toDartString()}');
        }

        final modulePath = dlInfo.ref.fileName.toDartString();
        final module = modules[modulePath] ??= NativeModule(
          id: modules.length,
          path: modulePath,
          baseAddress: dlInfo.ref.baseAddress.address,
          symbolName: sn != ffi.nullptr ? sn.toDartString() : '',
        );

        return NativeFrame(module: module, pc: addr);
      }).toList(growable: false);

      return NativeStack(
          frames: frames, modules: modules.values.toList(growable: false));
    });
  }
}

// const int kBasicResultLength = 65536;

// NativeStack captureStackOfTargetThread() {
//   return using((arena) {
//     // Invoke CollectStackTrace from helper library.
//     const maxStackDepth = 1024;
//     final outputBuffer = arena.allocate<Int64>(sizeOf<Int64>() * maxStackDepth);
//     final error = _collectStackTraceOfTargetThread(outputBuffer, maxStackDepth);
//     if (error != nullptr) {
//       final errorString = error.toDartString();
//       malloc.free(error);
//       throw StateError(errorString); // Something went wrong.
//     }

//     final dlInfo = arena.allocate<DlInfo>(sizeOf<DlInfo>());

//     // Process stack trace: which is a sequence of hexadecimal numbers
//     // separated by commas. For each frame try to locate base address
//     // of the module it belongs to using |dladdr|.
//     final modules = <String, NativeModule>{};
//     final frames = outputBuffer
//         .asTypedList(maxStackDepth)
//         .takeWhile((value) => value != 0)
//         .map((addr) {
//       final found = _dladdr(Pointer<Void>.fromAddress(addr), dlInfo);
//       if (found == 0) {
//         return NativeFrame(pc: addr);
//       }

//       final modulePath = dlInfo.ref.fileName.toDartString();
//       final module = modules[modulePath] ??= NativeModule(
//         id: modules.length,
//         path: modulePath,
//         baseAddress: dlInfo.ref.baseAddress.address,
//       );

//       return NativeFrame(module: module, pc: addr);
//     }).toList(growable: false);

//     return NativeStack(
//         frames: frames, modules: modules.values.toList(growable: false));
//   });
// }

void collectStack() {
  ffi.DynamicLibrary _loadLib() {
    const _libName = 'glance';
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('$_libName.dll');
    }

    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('lib$_libName.so');
    }

    return ffi.DynamicLibrary.process();
  }

  final binding = NativeIrisEventBinding(_loadLib());
  // final collect_stack

  binding.SetCurrentThreadAsTarget();

  Isolate.run(() async {
    final CircularBuffer<NativeFrame> circularBuffer = CircularBuffer(256);
    scheduleMicrotask(() {});
    try {
      while (true) {
        await Future.delayed(const Duration(milliseconds: 100));
        final collect_stack = NativeIrisEventBinding(_loadLib());
        final stack = collect_stack.captureStackOfTargetThread();

        final jsonMapList = stack.frames.map((frame) {
          circularBuffer.add(frame);
          if (frame.module != null) {
            final module = frame.module!;
            // print(
            //     "Frame(pc: ${frame.pc}, module: Module(path: ${module.path}, baseAddress: ${module.baseAddress}, symbolName: ${module.symbolName}))");

            return {
              "pc": frame.pc.toString(),
              "baseAddress": module.baseAddress.toString(),
              "path": module.path,
            };
          } else {
            // print("Frame(pc: ${frame.pc})");
            return {
              "pc": frame.pc.toString(),
            };
          }
        }).toList();

        // print(jsonEncode(jsonMapList));
        for (final json in jsonMapList) {
          print(jsonEncode(json));
        }

        // for (var frame in stack.frames) {
        //   if (frame.module != null) {
        //     final module = frame.module!;
        //     print(
        //         "Frame(pc: ${frame.pc}, module: Module(path: ${module.path}, baseAddress: ${module.baseAddress}, symbolName: ${module.symbolName}))");

        //     [
        //       {
        //         "pc": frame.pc.toString(),
        //         "baseAddress": module.baseAddress.toString(),
        //         "path": module.path,
        //       }
        //     ];
        //   } else {
        //     print("Frame(pc: ${frame.pc})");
        //   }
        // }
        print("");
      }
    } catch (e, st) {
      print('$e\n$st');
    }
  });
}

class CircularBuffer<T> {
  final List<T?> _buffer;
  final int _size;
  int _start = 0;
  int _end = 0;

  CircularBuffer(int size)
      : _size = size + 1, // Extra space to differentiate full from empty
        _buffer = List<T?>.filled(size + 1, null, growable: false);

  bool get isFull => (_end + 1) % _size == _start;

  bool get isEmpty => _start == _end;

  void add(T element) {
    if (isFull) {
      throw StateError('Buffer is full');
    }
    _buffer[_end] = element;
    _end = (_end + 1) % _size;
  }

  T? remove() {
    if (isEmpty) {
      throw StateError('Buffer is empty');
    }
    final element = _buffer[_start];
    _buffer[_start] = null; // Clear the slot
    _start = (_start + 1) % _size;
    return element;
  }

  List<T?> getContents() {
    if (isEmpty) {
      return [];
    }
    if (_end > _start) {
      return _buffer.sublist(_start, _end);
    } else {
      return _buffer.sublist(_start) + _buffer.sublist(0, _end);
    }
  }
}

class SampleThread {
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  int _idCounter = 0;
  bool _closed = false;

  void getSample(List<int> timestampRange) {

  }

  Future<Object?> parseJson(String message) async {
    if (_closed) throw StateError('Closed');
    final completer = Completer<Object?>.sync();
    final id = _idCounter++;
    _activeRequests[id] = completer;
    _commands.send((id, message));
    return await completer.future;
  }

  static Future<SampleThread> spawn() async {
    // Create a receive port and add its initial message handler
    final initPort = RawReceivePort();
    final connection = Completer<(ReceivePort, SendPort)>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete((
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ));
    };

    // Spawn the isolate.
    try {
      await Isolate.spawn(_startRemoteIsolate, (initPort.sendPort));
    } on Object {
      initPort.close();
      rethrow;
    }

    final (ReceivePort receivePort, SendPort sendPort) =
        await connection.future;

    return SampleThread._(receivePort, sendPort);
  }

  SampleThread._(this._responses, this._commands) {
    _responses.listen(_handleResponsesFromIsolate);
  }

  void _handleResponsesFromIsolate(dynamic message) {
    final (int id, Object? response) = message as (int, Object?);
    final completer = _activeRequests.remove(id)!;

    if (response is RemoteError) {
      completer.completeError(response);
    } else {
      completer.complete(response);
    }

    if (_closed && _activeRequests.isEmpty) _responses.close();
  }

  static void _handleCommandsToIsolate(
    ReceivePort receivePort,
    SendPort sendPort,
  ) {
    receivePort.listen((message) {
      if (message == 'shutdown') {
        receivePort.close();
        return;
      }
      final (int id, String jsonText) = message as (int, String);
      try {
        final jsonData = jsonDecode(jsonText);
        sendPort.send((id, jsonData));
      } catch (e) {
        sendPort.send((id, RemoteError(e.toString(), '')));
      }
    });
  }

  static void _startRemoteIsolate(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    _handleCommandsToIsolate(receivePort, sendPort);
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _commands.send('shutdown');
      if (_activeRequests.isEmpty) _responses.close();
      print('--- port closed --- ');
    }
  }
}

