import 'dart:developer';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
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

  @override
  bool isRunning = true;

  @override
  List<AggregatedNativeFrame> aggregateStacks(SamplerConfig config,
      RingBuffer<NativeStack> buffer, List<int> timestampRange) {
    return [];
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

    test('getStacktrace', () async {
      fakeAsync((async) async {
        stackCapturer = FakeStackCapturer();
        samplerProcessor = SamplerProcessor(
          SamplerConfig(
            jankThreshold: 1,
            modulePathFilters: [],
            sampleRateInMilliseconds: 1000,
          ),
          stackCapturer,
        );
        final now = Timeline.now;
        final module1 = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(
          pc: 540642472602,
          timestamp: now - 100,
          module: module1,
        );
        final module2 = NativeModule(
          id: 2,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'world',
        );
        final frame2 = NativeFrame(
          pc: 540642472608,
          timestamp: now - 200,
          module: module2,
        );

        stackCapturer.nativeStack =
            NativeStack(frames: [frame1, frame2], modules: [module1, module2]);

        samplerProcessor.setCurrentThreadAsTarget();
        samplerProcessor.loop();
        async.elapse(const Duration(milliseconds: 1500));
        final stackTraces = samplerProcessor.getStacktrace([now - 1000, now]);

        expect(stackTraces.length == 2, isTrue);
        // The order is reversed
        expect(stackTraces[0].frame, frame2);
        expect(stackTraces[1].frame, frame1);
      });
    });

    test('getStacktrace throw error if not call setCurrentThreadAsTarget', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(
          jankThreshold: 1,
          modulePathFilters: [],
          sampleRateInMilliseconds: 1000,
        ),
        stackCapturer,
      );
      final now = Timeline.now;
      final module1 = NativeModule(
        id: 1,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'hello',
      );
      final frame1 = NativeFrame(
        pc: 540642472602,
        timestamp: now - 100,
        module: module1,
      );
      final module2 = NativeModule(
        id: 2,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'world',
      );
      final frame2 = NativeFrame(
        pc: 540642472608,
        timestamp: now - 200,
        module: module2,
      );

      stackCapturer.nativeStack =
          NativeStack(frames: [frame1, frame2], modules: [module1, module2]);

      expect(
        () => samplerProcessor.getStacktrace([now - 1000, now]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('getStacktrace throw error if not call loop', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(
          jankThreshold: 1,
          modulePathFilters: [],
          sampleRateInMilliseconds: 1000,
        ),
        stackCapturer,
      );
      final now = Timeline.now;
      final module1 = NativeModule(
        id: 1,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'hello',
      );
      final frame1 = NativeFrame(
        pc: 540642472602,
        timestamp: now - 100,
        module: module1,
      );
      final module2 = NativeModule(
        id: 2,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'world',
      );
      final frame2 = NativeFrame(
        pc: 540642472608,
        timestamp: now - 200,
        module: module2,
      );

      stackCapturer.nativeStack =
          NativeStack(frames: [frame1, frame2], modules: [module1, module2]);

      samplerProcessor.setCurrentThreadAsTarget();

      expect(
        () => samplerProcessor.getStacktrace([now - 1000, now]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('getStacktrace after calling close', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(
          jankThreshold: 1,
          modulePathFilters: [],
          sampleRateInMilliseconds: 1000,
        ),
        stackCapturer,
      );
      final now = Timeline.now;
      final module1 = NativeModule(
        id: 1,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'hello',
      );
      final frame1 = NativeFrame(
        pc: 540642472602,
        timestamp: now - 100,
        module: module1,
      );
      final module2 = NativeModule(
        id: 2,
        path: 'libapp.so',
        baseAddress: 540641718272,
        symbolName: 'world',
      );
      final frame2 = NativeFrame(
        pc: 540642472608,
        timestamp: now - 200,
        module: module2,
      );

      stackCapturer.nativeStack =
          NativeStack(frames: [frame1, frame2], modules: [module1, module2]);

      samplerProcessor.setCurrentThreadAsTarget();
      samplerProcessor.close();

      expect(
        () => samplerProcessor.getStacktrace([now - 1000, now]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('loop', () {
      fakeAsync((async) async {
        stackCapturer = FakeStackCapturer();
        samplerProcessor = SamplerProcessor(
          SamplerConfig(
            jankThreshold: 1,
            modulePathFilters: [],
            sampleRateInMilliseconds: 1000,
          ),
          stackCapturer,
        );
        final now = Timeline.now;
        final module1 = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(
          pc: 540642472602,
          timestamp: now - 100,
          module: module1,
        );
        final module2 = NativeModule(
          id: 2,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'world',
        );
        final frame2 = NativeFrame(
          pc: 540642472608,
          timestamp: now - 200,
          module: module2,
        );
        final module3 = NativeModule(
          id: 3,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'world',
        );
        final frame3 = NativeFrame(
          pc: 540642472605,
          timestamp: now - 300,
          module: module3,
        );

        stackCapturer.nativeStack =
            NativeStack(frames: [frame1, frame2], modules: [module1, module2]);

        samplerProcessor.setCurrentThreadAsTarget();
        samplerProcessor.loop();
        // Trigger first loop
        async.elapse(const Duration(milliseconds: 1500));
        stackCapturer.nativeStack =
            NativeStack(frames: [frame3], modules: [module3]);
        // Trigger second loop
        async.elapse(const Duration(milliseconds: 1500));
        final stackTraces = samplerProcessor.getStacktrace([now - 1000, now]);
        // Close it avoid unnecessary loop in test
        samplerProcessor.close();

        expect(stackTraces.length == 3, isTrue);
        // The order is reversed
        expect(stackTraces[0].frame, frame3);
        expect(stackTraces[1].frame, frame2);
        expect(stackTraces[2].frame, frame1);
      });
    });

    test('close', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(
          jankThreshold: 1,
          modulePathFilters: [],
          sampleRateInMilliseconds: 1000,
        ),
        stackCapturer,
      );
      samplerProcessor.close();
      expect(samplerProcessor.isRunning, isFalse);
    });

    group('aggregateStacks', () {
      test('return aggregated frames', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 1,
          modulePathFilters: [],
          sampleRateInMilliseconds: 1000,
        );
        samplerProcessor = SamplerProcessor(
          config,
          stackCapturer,
        );
        final now = Timeline.now;
        final module1 = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(
          pc: 540642472602,
          timestamp: now - 100,
          module: module1,
        );
        final module2 = NativeModule(
          id: 2,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'world',
        );
        final frame2 = NativeFrame(
          pc: 540642472608,
          timestamp: now - 200,
          module: module2,
        );
        final module3 = NativeModule(
          id: 3,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'world',
        );
        final frame3 = NativeFrame(
          pc: 540642472605,
          timestamp: now - 300,
          module: module3,
        );

        final stack1 = NativeStack(frames: [frame1], modules: [module1]);
        final stack2 = NativeStack(frames: [frame2], modules: [module2]);
        final stack3 = NativeStack(frames: [frame3], modules: [module3]);
        final buffer = RingBuffer<NativeStack>(3)
          ..write(stack1)
          ..write(stack2)
          ..write(stack3);

        final timestampRange = <int>[now - 1000, now];
        final aggregatedNativeFrames =
            samplerProcessor.aggregateStacks(config, buffer, timestampRange);
        expect(aggregatedNativeFrames.length == 3, isTrue);
        expect(aggregatedNativeFrames[0], frame3);
        expect(aggregatedNativeFrames[1], frame2);
        expect(aggregatedNativeFrames[2], frame1);
      });

      test('return frames between the timestampRange', () {});

      test('return frames between the timestampRange', () {});

      test('return frames exceed the jankThreshold', () {});

      test('return filtered modules', () {});
    });
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
