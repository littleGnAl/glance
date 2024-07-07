import 'dart:developer';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/sampler.dart';

// class TestSamplerProcessorResult {
//   List<AggregatedNativeFrame> frames = [];
//   bool isLoop = false;
//   bool isSetCurrentThreadAsTarget = false;
// }

class _FakeSamplerProcessor implements SamplerProcessor {
  _FakeSamplerProcessor(this.sendPort, this.frames);

  final SendPort sendPort;

  final List<AggregatedNativeFrame> frames;
  // bool isLoop = false;
  // bool isSetCurrentThreadAsTarget = false;

  // TestSamplerProcessorResult testResult = TestSamplerProcessorResult();

  @override
  List<AggregatedNativeFrame> getStacktrace(List<int> timestampRange) {
    sendPort.send('getStacktrace');
    return frames;
  }

  @override
  Future<void> loop() async {
    // isLoop = true;
    // testResult.isLoop = true;
    sendPort.send('loop');
  }

  @override
  void setCurrentThreadAsTarget() {
    // isSetCurrentThreadAsTarget = true;

    // testResult.isSetCurrentThreadAsTarget = true;
    sendPort.send('setCurrentThreadAsTarget');
  }

  @override
  void close() {
    sendPort.send('close');
  }
}

class FakeSamplerProcessor {
  FakeSamplerProcessor() {
    receivePort.listen((data) {
      // result = data;
      funcCallQueue.add(data);
    });
  }
  final receivePort = ReceivePort();

  final funcCallQueue = <String>[];

  // TestSamplerProcessorResult result = TestSamplerProcessorResult();

  List<AggregatedNativeFrame> frames = [];

  SamplerProcessor get processor =>
      _FakeSamplerProcessor(receivePort.sendPort, frames);
}

SamplerProcessorFactory _samplerProcessorFactory(
    SendPort sendPort, List<AggregatedNativeFrame> frames) {
  return (config) {
    return _FakeSamplerProcessor(sendPort, frames);
  };
}

class FakeStackCapturer implements StackCapturer {
  bool isCaptureStackOfTargetThread = false;
  bool isSetCurrentThreadAsTarget = false;
  NativeStack nativeStack = NativeStack(frames: [], modules: []);

  @override
  NativeStack captureStackOfTargetThread() {
    isCaptureStackOfTargetThread = true;
    return nativeStack;
  }

  @override
  void setCurrentThreadAsTarget() {
    isSetCurrentThreadAsTarget = true;
  }
}

void main() {
  group('Sampler', () {
    late FakeSamplerProcessor processor;
    late Sampler sampler;

    test('create', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(SamplerConfig(
        jankThreshold: 1,
        modulePathFilters: [],
        samplerProcessorFactory:
            _samplerProcessorFactory(processor.receivePort.sendPort, []),
      ));
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));
      expect(processor.funcCallQueue.length == 2, isTrue);
      expect(processor.funcCallQueue[0], 'setCurrentThreadAsTarget');
      expect(processor.funcCallQueue[1], 'loop');
    });

    test('getSamples', () async {
      processor = FakeSamplerProcessor();
      final frame = AggregatedNativeFrame(NativeFrame(
        pc: 540642472608,
        timestamp: Timeline.now,
        module: NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        ),
      ));

      sampler = await Sampler.create(SamplerConfig(
        jankThreshold: 1,
        modulePathFilters: [],
        samplerProcessorFactory:
            _samplerProcessorFactory(processor.receivePort.sendPort, [frame]),
      ));

      final now = Timeline.now;
      final frames = await sampler.getSamples([now - 1000, now]);
      expect(frames, equals([frame]));

      expect(processor.funcCallQueue.length == 3, isTrue);
      expect(processor.funcCallQueue[2], 'getStacktrace');
    });

    test('close', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(SamplerConfig(
        jankThreshold: 1,
        modulePathFilters: [],
        samplerProcessorFactory:
            _samplerProcessorFactory(processor.receivePort.sendPort, []),
      ));
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));

      sampler.close();
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));
      expect(processor.funcCallQueue.length == 3, isTrue);
      expect(processor.funcCallQueue[2], 'close');
    });

    test('getSamples after calling close', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(SamplerConfig(
        jankThreshold: 1,
        modulePathFilters: [],
        samplerProcessorFactory:
            _samplerProcessorFactory(processor.receivePort.sendPort, []),
      ));

      sampler.close();

      expect(
          () async => sampler.getSamples([0, 1]), throwsA(isA<StateError>()));
    });
  });

  group('SamplerProcessor', () {
    late FakeStackCapturer stackCapturer;
    late SamplerProcessor samplerProcessor;

    test('setCurrentThreadAsTarget', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
          SamplerConfig(jankThreshold: 1, modulePathFilters: []),
          stackCapturer);
      samplerProcessor.setCurrentThreadAsTarget();
      expect(stackCapturer.isSetCurrentThreadAsTarget, isTrue);
    });

    test('getStacktrace', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
          SamplerConfig(jankThreshold: 1, modulePathFilters: []),
          stackCapturer);
      samplerProcessor.setCurrentThreadAsTarget();
      samplerProcessor.getStacktrace([0, 1]);
    });

    test('getStacktrace throw error if not call setCurrentThreadAsTarget',
        () {});

    test('getStacktrace after calling close', () {});

    test('loop', () {});

    test('stop looping after calling close', () {});

    test('close', () {});
  });

  group('RingBuffer', () {
    test('isEmpty', () {
      final buffer = RingBuffer<int>(1);
      expect(buffer.isEmpty, isTrue);
    });

    test('isFull', () {
      final buffer = RingBuffer<int>(1);
      buffer.write(1);
      expect(buffer.isFull, isTrue);
    });

    test('write a value', () {
      final buffer = RingBuffer<int>(2);
      buffer.write(1);
      expect(buffer.read() == 1, isTrue);
    });

    test('write a value after full', () {
      final buffer = RingBuffer<int>(2);
      buffer.write(1);
      buffer.write(2);
      buffer.write(3);
      expect(buffer.isFull, isTrue);
      expect(buffer.read() == 2, isTrue);
      expect(buffer.read() == 3, isTrue);
    });

    test('read a value', () {
      final buffer = RingBuffer<int>(1);
      buffer.write(1);
      expect(buffer.read() == 1, isTrue);
    });

    test('read a value when empty', () {
      final buffer = RingBuffer<int>(1);
      expect(buffer.read(), isNull);
    });

    test('readAll', () {
      final buffer = RingBuffer<int>(3);
      buffer.write(1);
      buffer.write(2);
      expect(buffer.readAll(), equals([1, 2]));
    });

    test('readAll after full', () {
      final buffer = RingBuffer<int>(2);
      buffer.write(1);
      buffer.write(2);
      buffer.write(3);
      expect(buffer.readAll(), equals([2, 3]));
    });
  });
}
