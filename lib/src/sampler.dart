import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:glance/src/collect_stack.dart';

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
  final List<AggregatedNativeFrame> data;
}

// class _SlowFunctionsDetectedResponse implements _Response {
//   const _SlowFunctionsDetectedResponse(this.id, this.data);
//   final int id;
//   final SlowFunctionsInformation data;
// }

/// 16ms
const int kDefaultSampleRateInMilliseconds = 16;

class SamplerConfig {
  SamplerConfig({
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
    required this.modulePathFilters,
  });

  /// e.g., libapp.so, libflutter.so
  final List<String> modulePathFilters;

  final int sampleRateInMilliseconds;
}

class Sampler {
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  int _idCounter = 0;
  bool _closed = false;

  // List<SlowFunctionsDetectedCallback> _slowFunctionsDetectedCallbackCallbacks =
  //     [];

  Future<List<AggregatedNativeFrame>> getSamples(
      List<int> timestampRange) async {
    if (_closed) throw StateError('Closed');
    final completer = Completer<Object?>.sync();
    final id = _idCounter++;
    _activeRequests[id] = completer;
    _commands.send(_GetSamplesRequest(id, timestampRange));
    final response = (await completer.future) as _GetSamplesResponse;
    return response.data;
  }

  // static ffi.DynamicLibrary _loadLib() {
  //   const _libName = 'glance';
  //   if (Platform.isWindows) {
  //     return ffi.DynamicLibrary.open('$_libName.dll');
  //   }

  //   if (Platform.isAndroid) {
  //     return ffi.DynamicLibrary.open('lib$_libName.so');
  //   }

  //   return ffi.DynamicLibrary.process();
  // }

  static Future<Sampler> create(SamplerConfig config) async {
    StackCapturer().setCurrentThreadAsTarget();

    // Create a receive port and add its initial message handler
    final initPort = RawReceivePort();
    // (ReceivePort, SendPort)
    final connection = Completer<List<Object>>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete([
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ]);
    };

    // Spawn the isolate.
    try {
      await Isolate.spawn(_startRemoteIsolate, [initPort.sendPort, config]);
    } on Object {
      initPort.close();
      rethrow;
    }

    // final (ReceivePort receivePort, SendPort sendPort) =
    //     await connection.future;
    final List<Object> msg = await connection.future;
    final receivePort = msg[0] as ReceivePort;
    final sendPort = msg[1] as SendPort;

    return Sampler._(receivePort, sendPort);
  }

  Sampler._(this._responses, this._commands) {
    _responses.listen(_handleResponsesFromIsolate);
  }

  // void addSlowFunctionsDetectedCallback(
  //     SlowFunctionsDetectedCallback callback) {
  //   _slowFunctionsDetectedCallbackCallbacks.add(callback);
  // }

  void _handleResponsesFromIsolate(dynamic message) {
    // if (message is _SlowFunctionsDetectedResponse) {
    //   for (final callback
    //       in List.from(_slowFunctionsDetectedCallbackCallbacks)) {
    //     callback(message.data);
    //   }
    //   return;
    // }

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
    SamplerConfig config,
  ) {
    final _SamplerProcessor collector = _SamplerProcessor(config);
    // collector.setSlowFunctionsDetectedCallback((info) {
    //   // print('setSlowFunctionsDetectedCallback');
    //   sendPort.send(_SlowFunctionsDetectedResponse(0, info));
    // });
    collector.loop();

    receivePort.listen((message) {
      if (message is _ShutdownRequest) {
        receivePort.close();
        return;
      }

      if (message is _GetSamplesRequest) {
        // int start = message.timestampRange[0];
        // int end = message.timestampRange[1];
        // // print('start: $start, end: $end');
        // // /lib/arm64/libflutter.so
        // List<String> pathFilters = <String>[
        //   'libflutter.so',
        //   'libapp.so',
        // ];
        final stacktrace = collector.getStacktrace(message.timestampRange);
        //     .where((e) {
        //   final frame = e.frame;

        //   // return e.timestamp >=start  && e.timestamp <= end;
        //   return frame.module != null &&
        //       // frame.timestamp >= start &&
        //       // frame.timestamp <= end &&
        //       pathFilters.any((pathFilter) {
        //         return frame.module?.path.contains(pathFilter) == true;
        //       });
        // }).toList();

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

  static void _startRemoteIsolate(List<Object> args) {
    SendPort sendPort = args[0] as SendPort;
    SamplerConfig config = args[1] as SamplerConfig;
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    _handleCommandsToIsolate(receivePort, sendPort, config);
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

class _SamplerProcessor {
  _SamplerProcessor(this.config);
  final SamplerConfig config;

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
  // With all default configurations, the length is approximately 641 (320 * 2 + 1) of 2s
  // refer to the dart sdk implementation.
  // https://github.com/dart-lang/sdk/blob/bcaf745a9be6c4af0c338c43e6304c9e1c4c5535/runtime/vm/profiler.cc#L642
  static const _bufferCount = 641;
  // static const _bufferCount = 2561;
  // static const _sampleRateInMilliseconds = 16;

  RingBuffer<NativeStack>? _circularBuffer;

  // LinkedHashMap<int, NativeFrameTimeSpent>? _frameTimeSpentMap;

  // SlowFunctionsDetectedCallback? _slowFunctionsDetectedCallback;
  // void setSlowFunctionsDetectedCallback(
  //     SlowFunctionsDetectedCallback callback) {
  //   _slowFunctionsDetectedCallback = callback;
  // }

  List<AggregatedNativeFrame> getStacktrace(List<int> timestampRange) {
    assert(_circularBuffer != null);
    return List.unmodifiable(
        _aggregateStacks(timestampRange, _circularBuffer!));
    // return [];
  }

  Future<void> loop() async {
    final sampleRateInMilliseconds = config.sampleRateInMilliseconds;

    try {
      while (true) {
        await Future.delayed(Duration(milliseconds: sampleRateInMilliseconds));
        final stackCapturer = StackCapturer();
        final stack = stackCapturer.captureStackOfTargetThread();

        _circularBuffer ??= RingBuffer<NativeStack>(_bufferCount);
        _circularBuffer!.write(stack);

        // final jsonMapList = stack.frames.map((frame) {
        //   List<String> pathFilters = <String>[
        //     'libflutter.so',
        //     'libapp.so',
        //   ];

        //   if (frame.module != null &&
        //       pathFilters.any((pathFilter) {
        //         return frame.module?.path.contains(pathFilter) == true;
        //       })) {
        //     // _circularBuffer?.write(frame);
        //   }

        //   if (frame.module != null) {
        //     final module = frame.module!;
        //     // print(
        //     //     "Frame(pc: ${frame.pc}, module: Module(path: ${module.path}, baseAddress: ${module.baseAddress}, symbolName: ${module.symbolName}))");

        //     return {
        //       "pc": frame.pc.toString(),
        //       "baseAddress": module.baseAddress.toString(),
        //       "path": module.path,
        //     };
        //   } else {
        //     // print("Frame(pc: ${frame.pc})");
        //     return {
        //       "pc": frame.pc.toString(),
        //     };
        //   }
        // }).toList();

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

  List<AggregatedNativeFrame> _aggregateStacks(
      List<int> timestampRange, RingBuffer<NativeStack> buffer) {
    List<String> pathFilters = config.modulePathFilters;
    // final sampleRateInMilliseconds = config.sampleRateInMilliseconds;

    // <String>[
    //   'libflutter.so',
    //   'libapp.so',
    // ];

    int start = timestampRange[0];
    int end = timestampRange[1];
    // final maps = LinkedHashMap<int, NativeFrameTimeSpent>();
    final frameTimeSpentMap =
        LinkedHashMap<int, AggregatedNativeFrame>.identity();
    final allFrames = buffer.readAll().expand((e) => e!.frames).where((frame) {
      // final frame = e.frame;

      // return e.timestamp >=start  && e.timestamp <= end;
      return frame.module != null &&
          frame.timestamp >= start &&
          frame.timestamp <= end &&
          pathFilters.any((pathFilter) {
            return frame.module?.path.contains(pathFilter) == true;
          });
    });

    // bool needReport = false;
    for (final frame in allFrames) {
      final pc = frame.pc;
      if (frameTimeSpentMap.containsKey(pc)) {
        final timeSpent = frameTimeSpentMap[pc]!;
        // final timestampInMacros =
        //     timeSpent.timestampInMacros + sampleRateInMilliseconds;
        // timeSpent.timestampInMacros = timestampInMacros;

        final occurTimes = timeSpent.occurTimes + 1;
        timeSpent.occurTimes = occurTimes;
      } else {
        final timeSpent = AggregatedNativeFrame(frame);
        timeSpent.occurTimes = 1;
        frameTimeSpentMap[pc] = timeSpent;
      }
    }

    return frameTimeSpentMap.values.toList().reversed.toList();

    // print('needReport: $needReport');
    // if (needReport) {
    //   _slowFunctionsDetectedCallback?.call(SlowFunctionsInformation(
    //       stackTraces: List.from(frameTimeSpentMap!.values),
    //       jankDuration: Duration()));
    //   // _frameTimeSpentMap!.clear();
    // }
  }
}

class RingBuffer<T> {
  final List<T?> _buffer;
  int _head = 0;
  int _tail = 0;
  bool _isFull = false;

  RingBuffer(int size) : _buffer = List<T?>.filled(size, null);

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
