import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'glance_internal.dart';

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
  final int timestamp;
  NativeFrame({
    this.module,
    required this.pc,
    required this.timestamp,
  });
}

class NativeFrameTimeSpent {
  final NativeFrame frame;
  int timestampInMacros = 0;
  NativeFrameTimeSpent(this.frame);

  // set timestampInMacros(int value) {
  //   _timestampInMacros = value;
  // }
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

  // TimestampNowInMicrosSinceEpoch

  int TimestampNowInMicrosSinceEpoch() {
    return _TimestampNowInMicrosSinceEpoch();
  }

  late final _TimestampNowInMicrosSinceEpochPtr =
      _lookup<ffi.NativeFunction<ffi.Int64 Function()>>(
          'TimestampNowInMicrosSinceEpoch');
  late final _TimestampNowInMicrosSinceEpoch =
      _TimestampNowInMicrosSinceEpochPtr.asFunction<int Function()>();

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
          return NativeFrame(
            pc: addr,
            timestamp:
                TimestampNowInMicrosSinceEpoch(), // DateTime.now().millisecondsSinceEpoch,
          );
        }

        // if (dlInfo.ref.symbolName != ffi.nullptr) {
        //   print(
        //       'dlInfo.ref.symbolName: ${dlInfo.ref.symbolName.toDartString()}');
        // }

        final sn = LookupSymbolName(dlInfo);
        // if (sn != ffi.nullptr) {
        //   print('sn: ${sn.toDartString()}');
        // }
        // if (dlInfo.ref.fileName != ffi.nullptr) {
        //   print('dlInfo.ref.fileName: ${dlInfo.ref.fileName.toDartString()}');
        // }

        final modulePath = dlInfo.ref.fileName.toDartString();
        final module = modules[modulePath] ??= NativeModule(
          id: modules.length,
          path: modulePath,
          baseAddress: dlInfo.ref.baseAddress.address,
          symbolName: sn != ffi.nullptr ? sn.toDartString() : '',
        );

        return NativeFrame(
          module: module,
          pc: addr,
          timestamp:
              TimestampNowInMicrosSinceEpoch(), // DateTime.now().millisecondsSinceEpoch,
        );
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

// void collectStack() {
//   ffi.DynamicLibrary _loadLib() {
//     const _libName = 'glance';
//     if (Platform.isWindows) {
//       return ffi.DynamicLibrary.open('$_libName.dll');
//     }

//     if (Platform.isAndroid) {
//       return ffi.DynamicLibrary.open('lib$_libName.so');
//     }

//     return ffi.DynamicLibrary.process();
//   }

//   final binding = NativeIrisEventBinding(_loadLib());
//   // final collect_stack

//   binding.SetCurrentThreadAsTarget();

//   Isolate.run(() async {
//     final CircularBuffer<NativeFrame> circularBuffer = CircularBuffer(256);
//     circularBuffer.readAll().where((e) => e != null);
//     scheduleMicrotask(() {});
//     try {
//       while (true) {
//         await Future.delayed(const Duration(milliseconds: 100));
//         final collect_stack = NativeIrisEventBinding(_loadLib());
//         final stack = collect_stack.captureStackOfTargetThread();

//         final jsonMapList = stack.frames.map((frame) {
//           circularBuffer.write(frame);
//           if (frame.module != null) {
//             final module = frame.module!;
//             // print(
//             //     "Frame(pc: ${frame.pc}, module: Module(path: ${module.path}, baseAddress: ${module.baseAddress}, symbolName: ${module.symbolName}))");

//             return {
//               "pc": frame.pc.toString(),
//               "baseAddress": module.baseAddress.toString(),
//               "path": module.path,
//             };
//           } else {
//             // print("Frame(pc: ${frame.pc})");
//             return {
//               "pc": frame.pc.toString(),
//             };
//           }
//         }).toList();

//         // print(jsonEncode(jsonMapList));
//         // for (final json in jsonMapList) {
//         //   print(jsonEncode(json));
//         // }

//         // for (var frame in stack.frames) {
//         //   if (frame.module != null) {
//         //     final module = frame.module!;
//         //     print(
//         //         "Frame(pc: ${frame.pc}, module: Module(path: ${module.path}, baseAddress: ${module.baseAddress}, symbolName: ${module.symbolName}))");

//         //     [
//         //       {
//         //         "pc": frame.pc.toString(),
//         //         "baseAddress": module.baseAddress.toString(),
//         //         "path": module.path,
//         //       }
//         //     ];
//         //   } else {
//         //     print("Frame(pc: ${frame.pc})");
//         //   }
//         // }
//         print("");
//       }
//     } catch (e, st) {
//       print('$e\n$st');
//     }
//   });
// }

class CircularBuffer<T> {
  final List<T?> _buffer;
  int _head = 0;
  int _tail = 0;
  bool _isFull = false;

  CircularBuffer(int size) : _buffer = List<T?>.filled(size, null);

  bool get isEmpty => !_isFull && _head == _tail;
  bool get isFull => _isFull;

  void write(T value) {
    if (_isFull) {
      _head = (_head + 1) % _buffer.length;
    }

    _buffer[_tail] = value;
    _tail = (_tail + 1) % _buffer.length;

    if (_tail == _head) {
      _isFull = true;
    }
  }

  T? read() {
    if (isEmpty) {
      return null;
    }

    final value = _buffer[_head];
    _buffer[_head] = null; // Clear the slot
    _head = (_head + 1) % _buffer.length;
    _isFull = false;

    return value;
  }

  List<T?> readAll() {
    List<T?> result = [];
    int current = _head;

    while (current != _tail || (_isFull && result.length < _buffer.length)) {
      result.add(_buffer[current]);
      current = (current + 1) % _buffer.length;
    }

    return result;
  }

  @override
  String toString() {
    return _buffer.toString();
  }
}

class StackCollector {
  // With all default configurations, the length is approximately 641 of 2s
  // based on the dart sdk implementation.
  // https://github.com/dart-lang/sdk/blob/bcaf745a9be6c4af0c338c43e6304c9e1c4c5535/runtime/vm/profiler.cc#L642
  static const _bufferCount = 641;
  // static const _bufferCount = 1281;
  static const _sampleRateInMilliseconds = 1;

  CircularBuffer<NativeFrame>? _circularBuffer;

  LinkedHashMap<int, NativeFrameTimeSpent>? _frameTimeSpentMap;

  SlowFunctionsDetectedCallback? _slowFunctionsDetectedCallback;
  void setSlowFunctionsDetectedCallback(
      SlowFunctionsDetectedCallback callback) {
    _slowFunctionsDetectedCallback = callback;
  }

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

  List<NativeFrame> getStacktrace() {
    // assert(circularBuffer != null);
    // return List.unmodifiable(circularBuffer!.readAll().where((e) => e != null));

    return [];
  }

  void setCurrentThreadAsTarget() {
    final binding = NativeIrisEventBinding(_loadLib());
    binding.SetCurrentThreadAsTarget();
  }

  Future<void> loop() async {
// max_profile_depth = Sample::kPCArraySizeInWords* kMaxSamplesPerTick,

// intptr_t Profiler::CalculateSampleBufferCapacity() {
//   if (FLAG_sample_buffer_duration <= 0) {
//     return SampleBlockBuffer::kDefaultBlockCount;
//   }
//   // Deeper stacks require more than a single Sample object to be represented
//   // correctly. These samples are chained, so we need to determine the worst
//   // case sample chain length for a single stack.
//   // Sample::kPCArraySizeInWords* kMaxSamplesPerTick / 4
//   // 32 * 4 / 4
//   const intptr_t max_sample_chain_length =
//       FLAG_max_profile_depth / kMaxSamplesPerTick;
//       // 2 * 1000 * （32 * 4 / 4）
//   const intptr_t sample_count = FLAG_sample_buffer_duration *
//                                 SamplesPerSecond() * max_sample_chain_length;
//       // （2 * 1000 * （32 * 4 / 4））/ 100 + 1
//   return (sample_count / SampleBlock::kSamplesPerBlock) + 1;
// }

    //

    try {
      while (true) {
        await Future.delayed(
            const Duration(milliseconds: _sampleRateInMilliseconds));
        final collect_stack = NativeIrisEventBinding(_loadLib());
        final stack = collect_stack.captureStackOfTargetThread();

        final circularBuffer = CircularBuffer<NativeFrame>(_bufferCount);

        final jsonMapList = stack.frames.map((frame) {
          List<String> pathFilters = <String>[
            'libflutter.so',
            'libapp.so',
          ];

          if (frame.module != null &&
              pathFilters.any((pathFilter) {
                return frame.module?.path.contains(pathFilter) == true;
              })) {
            circularBuffer?.write(frame);
          }

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
        // for (final json in jsonMapList) {
        //   print(jsonEncode(json));
        // }

        // print("");

        // aggregateStacks(circularBuffer);
      }
    } catch (e, st) {
      print('$e\n$st');
    }
  }

  void aggregateStacks(CircularBuffer<NativeFrame> buffer) {
    // final maps = LinkedHashMap<int, NativeFrameTimeSpent>();
    _frameTimeSpentMap ??= LinkedHashMap<int, NativeFrameTimeSpent>();
    final allFrames = buffer.readAll();
    bool needReport = false;
    for (final frame in allFrames) {
      final pc = frame!.pc;
      if (_frameTimeSpentMap!.containsKey(pc)) {
        final timeSpent = _frameTimeSpentMap![pc]!;
        final timestampInMacros =
            timeSpent.timestampInMacros + _sampleRateInMilliseconds;
        timeSpent.timestampInMacros = timestampInMacros;
        if (timestampInMacros > 0) {
          needReport = true;
        }
      } else {
        final timeSpent = NativeFrameTimeSpent(frame);
        timeSpent.timestampInMacros = _sampleRateInMilliseconds;
        _frameTimeSpentMap![pc] = timeSpent;
      }
    }

    if (needReport) {
      _slowFunctionsDetectedCallback?.call(SlowFunctionsInformation(
          stackTraces: List.from(_frameTimeSpentMap!.values),
          jankDuration: Duration()));
    }
  }
}

abstract class _Request {}

abstract class _Response {}

class _ShutdownRequest implements _Request {}

class _GetSamplesRequest implements _Request {
  const _GetSamplesRequest(this.id, this.timestampRange);
  final int id;
  final List<int> timestampRange;
}

class _GetSamplesResponse implements _Response {
  const _GetSamplesResponse(this.id, this.data);
  final int id;
  final List<NativeFrame> data;
}

class _SlowFunctionsDetectedResponse implements _Response {
  const _SlowFunctionsDetectedResponse(this.id, this.data);
  final int id;
  final SlowFunctionsInformation data;
}

class SampleThread {
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  int _idCounter = 0;
  bool _closed = false;

  List<SlowFunctionsDetectedCallback> _slowFunctionsDetectedCallbackCallbacks =
      [];

  Future<List<NativeFrame>> getSamples(List<int> timestampRange) async {
    if (_closed) throw StateError('Closed');
    final completer = Completer<Object?>.sync();
    final id = _idCounter++;
    _activeRequests[id] = completer;
    _commands.send(_GetSamplesRequest(id, timestampRange));
    final response = (await completer.future) as _GetSamplesResponse;
    return response.data;
  }

  static ffi.DynamicLibrary _loadLib() {
    const _libName = 'glance';
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('$_libName.dll');
    }

    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('lib$_libName.so');
    }

    return ffi.DynamicLibrary.process();
  }

  static Future<SampleThread> spawn() async {
    StackCollector().setCurrentThreadAsTarget();

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

  void addSlowFunctionsDetectedCallback(
      SlowFunctionsDetectedCallback callback) {
    _slowFunctionsDetectedCallbackCallbacks.add(callback);
  }

  void _handleResponsesFromIsolate(dynamic message) {
    if (message is _SlowFunctionsDetectedResponse) {
      for (final callback
          in List.from(_slowFunctionsDetectedCallbackCallbacks)) {
        callback(message.data);
      }
      return;
    }

    final _GetSamplesResponse response = message as _GetSamplesResponse;
    final completer = _activeRequests.remove(response.id)!;

    if (response is RemoteError) {
      completer.completeError(response);
    } else {
      // assert(response is _GetSamplesResponse);
      completer.complete(response);
    }

    if (_closed && _activeRequests.isEmpty) _responses.close();
  }

  static void _handleCommandsToIsolate(
    ReceivePort receivePort,
    SendPort sendPort,
  ) {
    final StackCollector collector = StackCollector();
    collector.setSlowFunctionsDetectedCallback((info) {
      sendPort.send(_SlowFunctionsDetectedResponse(0, info));
    });
    collector.loop();

    receivePort.listen((message) {
      if (message is _ShutdownRequest) {
        receivePort.close();
        return;
      }

      if (message is _GetSamplesRequest) {
        int start = message.timestampRange[0];
        int end = message.timestampRange[1];
        print('start: $start, end: $end');
        // /lib/arm64/libflutter.so
        List<String> pathFilters = <String>[
          'libflutter.so',
          'libapp.so',
        ];
        final stacktrace = collector.getStacktrace().where((e) {
          // return e.timestamp >=start  && e.timestamp <= end;
          return e.module != null &&
              pathFilters.any((pathFilter) {
                return e.module?.path.contains(pathFilter) == true;
              });
        }).toList();

        sendPort.send(_GetSamplesResponse(message.id, stacktrace));
        return;
      }

      print('Not reachable message: $message');
      // Not reachable.
      assert(false);

      // final (int id, String jsonText) = message as (int, String);
      // try {
      //   final jsonData = jsonDecode(jsonText);
      //   sendPort.send((id, jsonData));
      // } catch (e) {
      //   sendPort.send((id, RemoteError(e.toString(), '')));
      // }
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
