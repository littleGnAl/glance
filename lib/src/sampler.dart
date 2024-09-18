import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show compute;
import 'package:glance/glance.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/glance_impl.dart';
import 'package:glance/src/logger.dart';
import 'package:meta/meta.dart' show visibleForTesting;

abstract class _Request {}

abstract class _Response {}

class _ShutdownRequest implements _Request {}

class _GetSamplesRequest implements _Request {
  const _GetSamplesRequest(this.id, this.timestampRange);
  final int id;
  final List<int> timestampRange;
}

@visibleForTesting
class GetSamplesResponse implements _Response {
  const GetSamplesResponse(this.id, this.data);
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
    required this.stackTraceListener,
  });

  final int jankThreshold;

  /// e.g., libapp.so, libflutter.so
  final List<String> modulePathFilters;

  final int sampleRateInMilliseconds;

  /// The factory used to create a [SamplerProcessor]. This allows us to inject
  /// the [SamplerProcessor] in tests.
  final SamplerProcessorFactory samplerProcessorFactory;

  final StackTraceListener stackTraceListener;
}

typedef StackTraceListener = void Function(
    List<AggregatedNativeFrame> stackTraces);

/// Class to start a dedicated isolate for collecting stack traces.
class Sampler {
  Sampler._(this._processorIsolate, this._responses, this._commands,
      this._stackTraceListener) {
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

    return Sampler._(isolate, receivePort, sendPort, config.stackTraceListener);
  }

  final Isolate _processorIsolate;

  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _activeRequests = {};
  int _idCounter = 0;
  bool _closed = false;

  final StackTraceListener _stackTraceListener;

  Future<List<AggregatedNativeFrame>> getSamples(
      List<int> timestampRange) async {
    if (_closed) throw StateError('Closed');
    final completer = Completer<Object?>.sync();
    final id = _idCounter++;
    _activeRequests[id] = completer;
    _commands.send(_GetSamplesRequest(id, timestampRange));
    final response = (await completer.future) as GetSamplesResponse;
    return response.data;
  }

  void _handleResponsesFromIsolate(dynamic message) {
    final GetSamplesResponse response = message as GetSamplesResponse;
    // final completer = _activeRequests.remove(response.id)!;

    if (response is RemoteError) {
      // completer.completeError(response);
    } else {
      // completer.complete(response);
      // _reporter
      //     .report(JankReport(stackTrace: GlanceStackTraceImpl(response.data)));

      // print('response.data: ${response.data.length}');

      _stackTraceListener(response.data);
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
        // processor.getStackTrace(sendPort, message.id, message.timestampRange);
      } else {
        // Not reachable.
        assert(false);
      }
    });

    processor.loop(sendPort);
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
  // static const _bufferCount = 641;
  static const _bufferCount = 321;

  RingBuffer<NativeStack>? _buffer;

  void setCurrentThreadAsTarget() {
    _stackCapturer.setCurrentThreadAsTarget();
  }

  StackTraceMap<int, StackTraceMap<int, AggregatedNativeFrame>>
      _preStackTraceMap = StackTraceMap(99);

  List<AggregatedNativeFrame> _aggregatedFrames = [];
  bool _isWaitingAllFramesDone = false;

  /// Retrieves the aggregated [NativeFrame]s.
  ///
  /// The [NativeFrame]s are aggregated in a separate isolate using the [compute] function
  /// to prevent blocking the stack capture process. The result is sent directly to the [sendPort].
  Future<void> getStackTrace(
    SendPort sendPort,
    int messageId,
    List<int> timestampRange,
    RingBuffer<NativeStack> buffer,
    NativeStack nativeStack,
  ) async {
    assert(isRunning);
    assert(_buffer != null, 'Make sure you call `loop` first');

    // final args = [sendPort, _config, buffer!, timestampRange, messageId];
    // return compute((args) {
    //   final sendPort = (args as List)[0] as SendPort;
    //   final config = args[1] as SamplerConfig;
    //   final buffer = args[2] as RingBuffer<NativeStack>;
    //   final timestampRange = args[3] as List<int>;
    //   final id = args[4] as int;

    //   final stacktrace = aggregateStacks(config, buffer, timestampRange, 0);
    //   if (stacktrace.length > 90) {
    //     sendPort.send(GetSamplesResponse(id, stacktrace));
    //   }
    // }, args);

    final frames = aggregateStacks(
        _config, buffer, _preStackTraceMap, nativeStack, timestampRange, 0);
    if (frames.isNotEmpty) {
      _isWaitingAllFramesDone = true;
      if (_aggregatedFrames.isNotEmpty &&
          frames.first.frame.pc == _aggregatedFrames.first.frame.pc) {
        _isWaitingAllFramesDone = false;
        sendPort.send(GetSamplesResponse(0, frames));
        _aggregatedFrames.clear();
        _preStackTraceMap.clear();
        return;
      }

      _aggregatedFrames = frames;
    } else {
      _aggregatedFrames.clear();
    }
  }

  /// Start an infinite loop to capture the [NativeStack] at intervals specified
  /// by [SamplerConfig.sampleRateInMilliseconds]. The [NativeStack]s are stored
  /// in a [RingBuffer], and you can get the aggregated [NativeFrame]s using [getStackTrace].
  ///
  /// The loop will stop after you call [close].
  Future<void> loop(SendPort sendPort) async {
    // final streamController = StreamController();
    // streamController.stream.listen((data) {
    //   getStackTrace(sendPort, 0, [0, 0], data);
    // });

    final sampleRateInMilliseconds = _config.sampleRateInMilliseconds;
    _buffer ??= RingBuffer<NativeStack>(_bufferCount);

    int waitTime = 0;
    // sampleRateInMilliseconds * 1000;
    int now = Timeline.now;
    int nextTime = now + sampleRateInMilliseconds * 1000;
    int previousTime = now;

    final maxOccurTimes =
        _config.jankThreshold / _config.sampleRateInMilliseconds;
    final loopStartTime = Timeline.now;
    int loopCounter = 0;

    try {
      while (isRunning) {
        loopCounter++;
        now = Timeline.now;
        // if ((now + sampleRateInMilliseconds * 1000) > nextTime) {
        //   waitTime = nextTime - now;
        // }

        if (now > nextTime) {
          waitTime = 0;
        } else {
          waitTime = nextTime - now;
        }

        nextTime += sampleRateInMilliseconds * 1000;
        // print('waitTime: $waitTime');
        await Future.delayed(Duration(microseconds: waitTime));
        // await Future.delayed(Duration(milliseconds: sampleRateInMilliseconds));
        // previousTime = Timeline.now;
        if (!isRunning || _buffer == null) {
          return;
        }
        final stack = _stackCapturer.captureStackOfTargetThread();
        assert(_buffer != null);
        _buffer!.write(stack);

        // int current = Timeline.now;
        // int expectedLoopCount =
        //     ((current - loopStartTime) / (sampleRateInMilliseconds * 1000))
        //         .toInt();
        // final multipiler =
        //     ((expectedLoopCount - loopCounter) / expectedLoopCount);

        // int m = (maxOccurTimes - maxOccurTimes * multipiler).toInt();
        // print(
        //     'maxOccurTimes: $m, expectedLoopCount: $expectedLoopCount, loopCounter: $loopCounter, multipiler:$multipiler');

        // getStackTrace(sendPort, message.id, message.timestampRange);
        // Stopwatch stopwatch = Stopwatch()..start();
        // final stacktrace = aggregateStacks(_config, _buffer!, [], m);
        // // print('stacktrace; ${stacktrace.length}, stopwatch.elapsedMilliseconds: ${stopwatch.elapsedMilliseconds}');
        // if (stacktrace.length > 2) {
        //   _buffer = RingBuffer<NativeStack>(_bufferCount);
        //   sendPort.send(GetSamplesResponse(0, stacktrace));
        // }

        // getStackTrace(sendPort, 0, [0, 0]);

        // streamController.sink.add(_buffer!);

        getStackTrace(sendPort, 0, [0, 0], _buffer!, stack);
      }
    } catch (e, st) {
      GlanceLogger.log('error when running loop: $e\n$st');
    }
  }

  void close() {
    isRunning = false;
    _buffer = null;
  }

//   /// Aggregate the [NativeFrame]s by occurrence times.
//   @visibleForTesting
//   static List<AggregatedNativeFrame> aggregateStacks(
//     SamplerConfig config,
//     RingBuffer<NativeStack> buffer,
//     List<int> timestampRange,
//     int maxOccurTimes,
//   ) {
//     void addOrUpdateAggregatedNativeFrame(
//         SamplerConfig config,
//         List<int> timestampRange,
//         LinkedHashMap<int, AggregatedNativeFrame> aggregatedFrameMap,
//         NativeFrame frame) {
//       List<String> modulePathFilters = config.modulePathFilters;

//       // int start = timestampRange[0];
//       // int end = timestampRange[1];

//       final isInclude = frame.module != null &&
//           // frame.timestamp >= start &&
//           // frame.timestamp <= end &&
//           modulePathFilters.any((pathFilter) {
//             return RegExp(pathFilter).hasMatch(frame.module!.path);
//           });

//       if (!isInclude) {
//         return;
//       }
//       final pc = frame.pc;
//       if (aggregatedFrameMap.containsKey(pc)) {
//         final aggregatedFrame = aggregatedFrameMap[pc]!;
//         final occurTimes = aggregatedFrame.occurTimes + 1;
//         aggregatedFrame.occurTimes = occurTimes;
//         aggregatedFrame.frame = frame;
//       } else {
//         final aggregatedFrame = AggregatedNativeFrame(frame);
//         aggregatedFrameMap[pc] = aggregatedFrame;
//       }
//     }

//     final maxOccurTimes =
//         config.jankThreshold / config.sampleRateInMilliseconds;
//     // final maxOccurTimes = 1;
//     // print('maxOccurTimes: $maxOccurTimes');

//     final parentFrameMap = LinkedHashMap<int,
//         LinkedHashMap<int, AggregatedNativeFrame>>.identity();

//     for (final nativeStack in buffer.readAll().reversed) {
//       if (nativeStack?.frames.isEmpty == true) {
//         continue;
//       }
//       int parentFramePc = nativeStack!.frames.last.pc;
//       bool isContainParentFrame = parentFrameMap.containsKey(parentFramePc);

//       if (isContainParentFrame) {
//         final aggregatedFrameMap = parentFrameMap[parentFramePc]!;
//         final frames = nativeStack.frames;

//         // Aggregate from parent.
//         for (int i = frames.length - 1; i >= 0; --i) {
//           addOrUpdateAggregatedNativeFrame(
//               config, timestampRange, aggregatedFrameMap, frames[i]);
//         }
//       } else {
//         final aggregatedFrameMap =
//             LinkedHashMap<int, AggregatedNativeFrame>.identity();
//         final frames = nativeStack.frames;
//         for (int i = frames.length - 1; i >= 0; --i) {
//           addOrUpdateAggregatedNativeFrame(
//               config, timestampRange, aggregatedFrameMap, frames[i]);
//         }
//         parentFrameMap.putIfAbsent(parentFramePc, () => aggregatedFrameMap);
//       }
//     }

//     final allFrameList = <AggregatedNativeFrame>[];
//     for (final entry in parentFrameMap.entries) {
//       final jankFrames =
//           entry.value.values; //.where((e) => e.occurTimes > maxOccurTimes);
//       if (jankFrames.isNotEmpty) {
//         allFrameList.addAll(jankFrames.toList().reversed);
//       }
//     }

//     if (allFrameList.length > kMaxStackTraces) {
//       return allFrameList.sublist(0, kMaxStackTraces);
//     }

//     return allFrameList;
//   }

  /// Aggregate the [NativeFrame]s by occurrence times.
  @visibleForTesting
  static List<AggregatedNativeFrame> aggregateStacks(
    SamplerConfig config,
    RingBuffer<NativeStack> buffer,
    StackTraceMap<int, StackTraceMap<int, AggregatedNativeFrame>> stackTraceMap,
    NativeStack nativeStack,
    List<int> timestampRange,
    int maxOccurTimes,
  ) {
    void addOrUpdateAggregatedNativeFrame(
        SamplerConfig config,
        List<int> timestampRange,
        LinkedHashMap<int, AggregatedNativeFrame> aggregatedFrameMap,
        NativeFrame frame) {
      List<String> modulePathFilters = config.modulePathFilters;

      // int start = timestampRange[0];
      // int end = timestampRange[1];

      final isInclude = frame.module != null &&
          // frame.timestamp >= start &&
          // frame.timestamp <= end &&
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

    final maxOccurTimes =
        config.jankThreshold / config.sampleRateInMilliseconds;
    // final maxOccurTimes = 1;
    // print('maxOccurTimes: $maxOccurTimes');

    // final parentFrameMap =
    //     StackTraceMap<int, LinkedHashMap<int, AggregatedNativeFrame>>(99);

    // for (final nativeStack in buffer.readAll().reversed) {
    //   if (nativeStack?.frames.isEmpty == true) {
    //     continue;
    //   }
    //   int parentFramePc = nativeStack!.frames.last.pc;
    //   bool isContainParentFrame = parentFrameMap.containsKey(parentFramePc);

    //   if (isContainParentFrame) {
    //     final aggregatedFrameMap = parentFrameMap[parentFramePc]!;
    //     final frames = nativeStack.frames;

    //     // Aggregate from parent.
    //     for (int i = frames.length - 1; i >= 0; --i) {
    //       addOrUpdateAggregatedNativeFrame(
    //           config, timestampRange, aggregatedFrameMap, frames[i]);
    //     }
    //   } else {
    //     final aggregatedFrameMap =
    //         StackTraceMap<int, AggregatedNativeFrame>(99);
    //     final frames = nativeStack.frames;
    //     for (int i = frames.length - 1; i >= 0; --i) {
    //       addOrUpdateAggregatedNativeFrame(
    //           config, timestampRange, aggregatedFrameMap, frames[i]);
    //     }
    //     parentFrameMap.putIfAbsent(parentFramePc, () => aggregatedFrameMap);
    //   }
    // }

    if (nativeStack.frames.isEmpty == true) {
      // continue;
      return [];
    }
    int parentFramePc = nativeStack!.frames.last.pc;
    bool isContainParentFrame = stackTraceMap.containsKey(parentFramePc);

    if (isContainParentFrame) {
      final aggregatedFrameMap = stackTraceMap[parentFramePc]!;
      final frames = nativeStack.frames;

      // Aggregate from parent.
      for (int i = frames.length - 1; i >= 0; --i) {
        addOrUpdateAggregatedNativeFrame(
            config, timestampRange, aggregatedFrameMap, frames[i]);
      }
    } else {
      final aggregatedFrameMap = StackTraceMap<int, AggregatedNativeFrame>(99);
      final frames = nativeStack.frames;
      for (int i = frames.length - 1; i >= 0; --i) {
        addOrUpdateAggregatedNativeFrame(
            config, timestampRange, aggregatedFrameMap, frames[i]);
      }
      stackTraceMap.putIfAbsent(parentFramePc, () => aggregatedFrameMap);
    }

    final allFrameList = <AggregatedNativeFrame>[];
    for (final entry in stackTraceMap.entries) {
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

class StackTraceMap<K, V> implements LinkedHashMap<K, V> {
  StackTraceMap(this.capacity) : _map = LinkedHashMap.identity();

  final int capacity;
  final LinkedHashMap<K, V> _map;

  void _removeIf() {
    if (_map.length >= capacity) {
      _map.remove(_map.keys.first);
    }
  }

  @override
  V? operator [](Object? key) => _map[key];

  @override
  void operator []=(K key, V value) {
    _removeIf();
    _map[key] = value;
  }

  @override
  void addAll(Map<K, V> other) => _map.addAll(other);

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) =>
      _map.addEntries(newEntries);

  @override
  Map<RK, RV> cast<RK, RV>() => _map.cast();

  @override
  void clear() => _map.clear();

  @override
  bool containsKey(Object? key) => _map.containsKey(key);

  @override
  bool containsValue(Object? value) => _map.containsValue(value);

  @override
  // TODO: implement entries
  Iterable<MapEntry<K, V>> get entries => _map.entries;

  @override
  void forEach(void Function(K key, V value) action) => _map.forEach(action);
  @override
  // TODO: implement isEmpty
  bool get isEmpty => _map.isEmpty;

  @override
  // TODO: implement isNotEmpty
  bool get isNotEmpty => _map.isNotEmpty;

  @override
  // TODO: implement keys
  Iterable<K> get keys => _map.keys;

  @override
  // TODO: implement length
  int get length => _map.length;

  @override
  Map<K2, V2> map<K2, V2>(MapEntry<K2, V2> Function(K key, V value) convert) =>
      _map.map(convert);

  @override
  V putIfAbsent(K key, V Function() ifAbsent) {
    _removeIf();
    return _map.putIfAbsent(key, ifAbsent);
  }

  @override
  V? remove(Object? key) => _map.remove(key);

  @override
  void removeWhere(bool Function(K key, V value) test) =>
      _map.removeWhere(test);

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) =>
      _map.update(key, update);

  @override
  void updateAll(V Function(K key, V value) update) => _map.updateAll(update);

  @override
  // TODO: implement values
  Iterable<V> get values => _map.values;
} // identity

