import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/logger.dart';

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

  /// The factory used to create a [SamplerProcessor]. This allows us to inject
  /// the [SamplerProcessor] in tests.
  final SamplerProcessorFactory samplerProcessorFactory;
}

/// Class to start a dedicated isolate for collecting stack traces.
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
    final _GetSamplesResponse response = message as _GetSamplesResponse;
    final completer = _activeRequests.remove(response.id)!;

    if (response is RemoteError) {
      completer.completeError(response);
    } else {
      completer.complete(response);
    }
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
        final stacktrace = processor.getStackTrace(message.timestampRange);
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
      _processorIsolate.kill(priority: Isolate.beforeNextEvent);
    }
  }
}

class AggregatedNativeFrame {
  AggregatedNativeFrame(this.frame, {this.occurTimes = 1});
  NativeFrame frame;
  int occurTimes = 1;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is AggregatedNativeFrame &&
        frame == other.frame &&
        occurTimes == other.occurTimes;
  }

  @override
  int get hashCode => Object.hash(frame, occurTimes);
}

typedef SamplerProcessorFactory = SamplerProcessor Function(
    SamplerConfig config);

/// Class for processing the native frames.
class SamplerProcessor {
  SamplerProcessor(this._config, this._stackCapturer);
  final SamplerConfig _config;
  final StackCapturer _stackCapturer;
  @visibleForTesting
  bool isRunning = true;

  /// With all default configurations, the length is approximately 641 of 2s
  /// Refer to the dart sdk implementation.
  /// https://github.com/dart-lang/sdk/blob/bcaf745a9be6c4af0c338c43e6304c9e1c4c5535/runtime/vm/profiler.cc#L642
  static const _bufferCount = 641;

  RingBuffer<NativeStack>? _buffer;

  void setCurrentThreadAsTarget() {
    _stackCapturer.setCurrentThreadAsTarget();
  }

  /// Get the aggregated [NativeFrame]s.
  List<AggregatedNativeFrame> getStackTrace(List<int> timestampRange) {
    assert(isRunning);
    assert(_buffer != null, 'Make sure you call `loop` first');
    return aggregateStacks(_config, _buffer!, timestampRange);
  }

  /// Start an infinite loop to capture the [NativeStack] at intervals specified
  /// by [SamplerConfig.sampleRateInMilliseconds]. The [NativeStack]s are stored
  /// in a [RingBuffer], and you can get the aggregated [NativeFrame]s using [getStackTrace].
  ///
  /// The loop will stop after you call [close].
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
      GlanceLogger.log('error when running loop: $e\n$st');
    }
  }

  void close() {
    isRunning = false;
    _buffer = null;
  }

  void _addOrUpdateAggregatedNativeFrame(
      SamplerConfig config,
      List<int> timestampRange,
      LinkedHashMap<int, AggregatedNativeFrame> aggregatedFrameMap,
      NativeFrame frame) {
    List<String> modulePathFilters = config.modulePathFilters;

    int start = timestampRange[0];
    int end = timestampRange[1];

    final isInclude = frame.module != null &&
        frame.timestamp >= start &&
        frame.timestamp <= end &&
        modulePathFilters.any((pathFilter) {
          return RegExp(pathFilter).hasMatch(frame.module!.path);
        });

    if (!isInclude) {
      return;
    }
    final pc = frame.pc;
    if (aggregatedFrameMap.containsKey(pc)) {
      final aggregatedFrame = aggregatedFrameMap[pc]!;
      final occurTimes = aggregatedFrame.occurTimes + 1;
      aggregatedFrame.occurTimes = occurTimes;
      aggregatedFrame.frame = frame;
    } else {
      final aggregatedFrame = AggregatedNativeFrame(frame);
      aggregatedFrameMap[pc] = aggregatedFrame;
    }
  }

  /// Aggregate the [NativeFrame]s by occurrence times.
  @visibleForTesting
  List<AggregatedNativeFrame> aggregateStacks(
    SamplerConfig config,
    RingBuffer<NativeStack> buffer,
    List<int> timestampRange,
  ) {
    final maxOccurTimes =
        config.jankThreshold / config.sampleRateInMilliseconds;

    final parentFrameMap = LinkedHashMap<int,
        LinkedHashMap<int, AggregatedNativeFrame>>.identity();

    for (final nativeStack in buffer.readAll().reversed) {
      int parentFramePc = nativeStack!.frames.last.pc;
      bool isContainParentFrame = parentFrameMap.containsKey(parentFramePc);

      if (isContainParentFrame) {
        final aggregatedFrameMap = parentFrameMap[parentFramePc]!;
        final frames = nativeStack.frames;

        // Aggregate from parent.
        for (int i = frames.length - 1; i >= 0; --i) {
          _addOrUpdateAggregatedNativeFrame(
              config, timestampRange, aggregatedFrameMap, frames[i]);
        }
      } else {
        final aggregatedFrameMap =
            LinkedHashMap<int, AggregatedNativeFrame>.identity();
        final frames = nativeStack.frames;
        for (int i = frames.length - 1; i >= 0; --i) {
          _addOrUpdateAggregatedNativeFrame(
              config, timestampRange, aggregatedFrameMap, frames[i]);
        }
        parentFrameMap.putIfAbsent(parentFramePc, () => aggregatedFrameMap);
      }
    }

    final allFrameList = <AggregatedNativeFrame>[];
    for (final entry in parentFrameMap.entries) {
      final jankFrames =
          entry.value.values.where((e) => e.occurTimes > maxOccurTimes);
      if (jankFrames.isNotEmpty) {
        allFrameList.addAll(jankFrames.toList().reversed);
      }
    }

    if (allFrameList.length > kMaxStackTraces) {
      return allFrameList.sublist(0, kMaxStackTraces);
    }

    return allFrameList;
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
