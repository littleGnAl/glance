import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';

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

// /// 16ms
// const int kDefaultSampleRateInMilliseconds = 16;

SamplerProcessor _defaultSamplerProcessorFactory(SamplerConfig config) {
  return SamplerProcessor(config, StackCapturer());
}

class SamplerConfig {
  SamplerConfig({
    required this.jankThreshold,
    this.sampleRateInMilliseconds = kDefaultSampleRateInMilliseconds,
    required this.modulePathFilters,
    this.samplerProcessorFactory = _defaultSamplerProcessorFactory,
  });

  final int jankThreshold;

  /// e.g., libapp.so, libflutter.so
  final List<String> modulePathFilters;

  final int sampleRateInMilliseconds;

  final SamplerProcessorFactory samplerProcessorFactory;
}

class Sampler {
  Sampler._(this._processorIsolate, this._responses, this._commands) {
    _responses.listen(_handleResponsesFromIsolate);
  }

  static Future<Sampler> create(SamplerConfig config) async {
    final processor = config.samplerProcessorFactory(config);
    processor.setCurrentThreadAsTarget();

    // Create a receive port and add its initial message handler
    final initPort = RawReceivePort();
    final connection = Completer<List<Object>>.sync();
    initPort.handler = (initialMessage) {
      final commandPort = initialMessage as SendPort;
      connection.complete([
        ReceivePort.fromRawReceivePort(initPort),
        commandPort,
      ]);
    };

    late Isolate isolate;
    try {
      isolate =
          await Isolate.spawn(_samplerIsolate, [initPort.sendPort, config]);
    } on Object {
      initPort.close();
      rethrow;
    }

    // final (ReceivePort receivePort, SendPort sendPort) =
    //     await connection.future;
    final List<Object> msg = await connection.future;
    final receivePort = msg[0] as ReceivePort;
    final sendPort = msg[1] as SendPort;

    return Sampler._(isolate, receivePort, sendPort);
  }

  final Isolate _processorIsolate;

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

    // if (_closed && _activeRequests.isEmpty) _responses.close();
  }

  static void _samplerIsolate(List<Object> args) {
    SendPort sendPort = args[0] as SendPort;
    SamplerConfig config = args[1] as SamplerConfig;
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    final SamplerProcessor processor = config.samplerProcessorFactory(config);

    receivePort.listen((message) {
      if (message is _ShutdownRequest) {
        processor.close();
        receivePort.close();
      } else if (message is _GetSamplesRequest) {
        final stacktrace = processor.getStacktrace(message.timestampRange);
        sendPort.send(_GetSamplesResponse(message.id, stacktrace));
      } else {
        // Not reachable.
        assert(false);
      }
    });

    processor.loop();
  }

  void close() {
    if (!_closed) {
      _closed = true;
      _commands.send(_ShutdownRequest());
      _responses.close();
      _activeRequests.clear();
      _processorIsolate.kill(priority: Isolate.immediate);
    }
  }
}

typedef SamplerProcessorFactory = SamplerProcessor Function(
    SamplerConfig config);

class SamplerProcessor {
  SamplerProcessor(this._config, this._stackCapturer);
  final SamplerConfig _config;
  final StackCapturer _stackCapturer;
  @visibleForTesting
  bool isRunning = true;
  bool _debugCalledSetCurrentThreadAsTarget = false;

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

  RingBuffer<NativeStack>? _buffer;

  void setCurrentThreadAsTarget() {
    assert(() {
      _debugCalledSetCurrentThreadAsTarget = true;
      return true;
    }());
    _stackCapturer.setCurrentThreadAsTarget();
  }

  List<AggregatedNativeFrame> getStacktrace(List<int> timestampRange) {
    assert(_debugCalledSetCurrentThreadAsTarget,
        'Make sure you call `setCurrentThreadAsTarget` first');
    assert(isRunning);
    assert(_buffer != null, 'Make sure you call `loop` first');
    return aggregateStacks(_config, _buffer!, timestampRange);
  }

  Future<void> loop() async {
    final sampleRateInMilliseconds = _config.sampleRateInMilliseconds;
    _buffer ??= RingBuffer<NativeStack>(_bufferCount);

    try {
      while (isRunning) {
        await Future.delayed(Duration(milliseconds: sampleRateInMilliseconds));
        if (!isRunning || _buffer == null) {
          return;
        }
        final stack = _stackCapturer.captureStackOfTargetThread();
        assert(_buffer != null);
        _buffer!.write(stack);
      }
    } catch (e, st) {
      print('$e\n$st');
    }
  }

  void close() {
    isRunning = false;
    _buffer = null;
  }

  @visibleForTesting
  List<AggregatedNativeFrame> aggregateStacks(
    SamplerConfig config,
    RingBuffer<NativeStack> buffer,
    List<int> timestampRange,
  ) {
    List<String> pathFilters = config.modulePathFilters;
    // final sampleRateInMilliseconds = config.sampleRateInMilliseconds;
    final maxOccurTimes =
        config.jankThreshold / config.sampleRateInMilliseconds;

    int start = timestampRange[0];
    int end = timestampRange[1];
    // final maps = LinkedHashMap<int, NativeFrameTimeSpent>();
    final frameTimeSpentMap =
        LinkedHashMap<int, AggregatedNativeFrame>.identity();
    final allFrames = buffer.readAll().expand((e) => e!.frames).where((frame) {
      return frame.module != null &&
          frame.timestamp >= start &&
          frame.timestamp <= end &&
          pathFilters.any((pathFilter) {
            return RegExp(pathFilter).hasMatch(frame.module!.path);
          });
    });

    // bool needReport = false;
    for (final frame in allFrames) {
      final pc = frame.pc;
      if (frameTimeSpentMap.containsKey(pc)) {
        final timeSpent = frameTimeSpentMap[pc]!;
        final occurTimes = timeSpent.occurTimes + 1;
        timeSpent.occurTimes = occurTimes;
        timeSpent.frame = frame;
      } else {
        final timeSpent = AggregatedNativeFrame(frame);
        timeSpent.occurTimes = 1;
        frameTimeSpentMap[pc] = timeSpent;
      }
    }

    final ret = frameTimeSpentMap.values.toList();
    final len = ret.length;
    int subStart = 0;
    int subEnd = frameTimeSpentMap.values.length - 1;
    while (subStart < len && ret[subStart].occurTimes <= maxOccurTimes) {
      ++subStart;
    }
    while (subEnd >= 0 && ret[subEnd].occurTimes <= maxOccurTimes) {
      --subEnd;
    }

    final returnV = <AggregatedNativeFrame>[];
    // Reverse and sub list
    for (int i = subEnd, j = 0; i >= subStart; --i, ++j) {
      returnV.add(ret[i]);
    }
    return returnV;
  }
}

class RingBuffer<T extends Object> {
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
