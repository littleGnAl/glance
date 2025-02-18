import 'dart:developer';
import 'dart:isolate';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/constants.dart';
import 'package:glance/src/sampler.dart';

class _FakeSamplerProcessor implements SamplerProcessor {
  _FakeSamplerProcessor(this.sendPort, this.frames);

  final SendPort sendPort;

  final List<AggregatedNativeFrame> frames;

  int id = 0;

  @override
  Future<void> getStackTrace(
    SendPort stackTraceSendPort,
    int messageId,
    List<int> timestampRange,
  ) async {
    sendPort.send('getStackTrace');
    stackTraceSendPort.send(GetSamplesResponse(id++, frames));
  }

  @override
  Future<void> loop() async {
    sendPort.send('loop');
  }

  @override
  void setCurrentThreadAsTarget() {
    sendPort.send('setCurrentThreadAsTarget');
  }

  @override
  void close() {
    sendPort.send('close');
  }

  @override
  bool isRunning = true;
}

class FakeSamplerProcessor {
  FakeSamplerProcessor() {
    receivePort.listen((data) {
      funcCallQueue.add(data);
    });
  }
  final receivePort = ReceivePort();

  final funcCallQueue = <String>[];

  List<AggregatedNativeFrame> frames = [];
}

SamplerProcessorFactory _samplerProcessorFactory(
  SendPort sendPort,
  List<AggregatedNativeFrame> frames,
) {
  return (config) {
    return _FakeSamplerProcessor(sendPort, frames);
  };
}

class FakeStackCapturer implements StackCapturer {
  bool isCaptureStackOfTargetThread = false;
  bool isSetCurrentThreadAsTarget = false;
  bool isDisposed = false;
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

  @override
  void dispose() {
    isDisposed = true;
  }
}

void main() {
  group('Sampler', () {
    late FakeSamplerProcessor processor;
    late Sampler sampler;

    test('create', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(
        SamplerConfig(
          jankThreshold: 1,
          samplerProcessorFactory: _samplerProcessorFactory(
            processor.receivePort.sendPort,
            [],
          ),
        ),
      );
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));

      expect(processor.funcCallQueue.length, 2);
      expect(processor.funcCallQueue[0], 'setCurrentThreadAsTarget');
      expect(processor.funcCallQueue[1], 'loop');

      sampler.close();
    });

    test('getSamples', () async {
      processor = FakeSamplerProcessor();
      final frame = AggregatedNativeFrame(
        NativeFrame(
          pc: 540642472608,
          timestamp: Timeline.now,
          module: NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          ),
        ),
      );

      sampler = await Sampler.create(
        SamplerConfig(
          jankThreshold: 1,
          samplerProcessorFactory: _samplerProcessorFactory(
            processor.receivePort.sendPort,
            [frame],
          ),
        ),
      );

      final now = Timeline.now;
      final frames = await sampler.getSamples([now - 1000, now]);
      expect(frames, equals([frame]));

      expect(processor.funcCallQueue.length, 3);
      expect(processor.funcCallQueue[2], 'getStackTrace');

      sampler.close();
    });

    test('close', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(
        SamplerConfig(
          jankThreshold: 1,
          samplerProcessorFactory: _samplerProcessorFactory(
            processor.receivePort.sendPort,
            [],
          ),
        ),
      );
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));

      sampler.close();
      // Delay 500ms to ensure we receive all the responses from the send port
      await Future.delayed(const Duration(milliseconds: 500));
      expect(processor.funcCallQueue.length, 3);
      expect(processor.funcCallQueue[2], 'close');
    });

    test('getSamples after calling close', () async {
      processor = FakeSamplerProcessor();

      sampler = await Sampler.create(
        SamplerConfig(
          jankThreshold: 1,
          samplerProcessorFactory: _samplerProcessorFactory(
            processor.receivePort.sendPort,
            [],
          ),
        ),
      );

      sampler.close();

      expect(
        () async => sampler.getSamples([0, 1]),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('SamplerProcessor', () {
    late FakeStackCapturer stackCapturer;
    late SamplerProcessor samplerProcessor;

    test('setCurrentThreadAsTarget', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(jankThreshold: 1),
        stackCapturer,
      );
      samplerProcessor.setCurrentThreadAsTarget();
      expect(stackCapturer.isSetCurrentThreadAsTarget, isTrue);
    });

    test('getStackTrace', () async {
      fakeAsync((async) async {
        stackCapturer = FakeStackCapturer();
        samplerProcessor = SamplerProcessor(
          SamplerConfig(jankThreshold: 1, sampleRateInMilliseconds: 1000),
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

        stackCapturer.nativeStack = NativeStack(
          frames: [frame1, frame2],
          modules: [module1, module2],
        );

        samplerProcessor.setCurrentThreadAsTarget();
        samplerProcessor.loop();
        async.elapse(const Duration(milliseconds: 1500));

        final receivePort = ReceivePort();
        final response = receivePort.take(1);
        final sendPort = receivePort.sendPort;
        await samplerProcessor.getStackTrace(sendPort, 1, [now - 1000, now]);
        final stackTraces =
            (await response.cast<GetSamplesResponse>().first).data;

        expect(stackTraces.length, 2);
        // The order is reversed
        expect(stackTraces[0].frame, frame2);
        expect(stackTraces[1].frame, frame1);
      });
    });

    test('getStackTrace throw error if not call loop', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(jankThreshold: 1, sampleRateInMilliseconds: 1000),
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

      stackCapturer.nativeStack = NativeStack(
        frames: [frame1, frame2],
        modules: [module1, module2],
      );

      samplerProcessor.setCurrentThreadAsTarget();

      final receivePort = ReceivePort();
      final sendPort = receivePort.sendPort;

      expect(
        () => (samplerProcessor.getStackTrace(sendPort, 1, [now - 1000, now])),
        throwsA(isA<AssertionError>()),
      );
    });

    test('getStackTrace after calling close', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(jankThreshold: 1, sampleRateInMilliseconds: 1000),
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

      stackCapturer.nativeStack = NativeStack(
        frames: [frame1, frame2],
        modules: [module1, module2],
      );

      samplerProcessor.setCurrentThreadAsTarget();
      samplerProcessor.close();

      final receivePort = ReceivePort();

      final sendPort = receivePort.sendPort;

      expect(
        () => samplerProcessor.getStackTrace(sendPort, 1, [now - 1000, now]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('loop', () async {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(jankThreshold: 1, sampleRateInMilliseconds: 1000),
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

      samplerProcessor.setCurrentThreadAsTarget();

      fakeAsync((async) {
        stackCapturer.nativeStack = NativeStack(
          frames: [frame1, frame2],
          modules: [module1, module2],
        );

        samplerProcessor.loop();
        // Trigger the first loop
        async.elapse(const Duration(milliseconds: 1500));
        stackCapturer.nativeStack = NativeStack(
          frames: [frame3],
          modules: [module3],
        );
        // Trigger the second loop
        async.elapse(const Duration(milliseconds: 1500));
      });

      final receivePort = ReceivePort();
      final response = receivePort.take(1);
      final sendPort = receivePort.sendPort;

      samplerProcessor.getStackTrace(sendPort, 1, [now - 1000, now]);
      final stackTraces =
          (await response.cast<GetSamplesResponse>().first).data;

      // Close it avoid unnecessary loop in test
      samplerProcessor.close();

      expect(stackTraces.length == 3, isTrue);
      // The order is reversed
      expect(stackTraces[0].frame, frame3);
      expect(stackTraces[1].frame, frame1);
      expect(stackTraces[2].frame, frame2);
    });

    test('close', () {
      stackCapturer = FakeStackCapturer();
      samplerProcessor = SamplerProcessor(
        SamplerConfig(jankThreshold: 1, sampleRateInMilliseconds: 1000),
        stackCapturer,
      );
      samplerProcessor.close();
      expect(samplerProcessor.isRunning, isFalse);
      expect(stackCapturer.isDisposed, isTrue);
    });

    group('aggregateStacks', () {
      test('return aggregated frames with one frame in stack', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 1,
          sampleRateInMilliseconds: 1000,
        );
        samplerProcessor = SamplerProcessor(config, stackCapturer);
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
          symbolName: 'helloworld',
        );
        final frame3 = NativeFrame(
          pc: 540642472605,
          timestamp: now - 300,
          module: module3,
        );

        final stack1 = NativeStack(frames: [frame1], modules: [module1]);
        final stack2 = NativeStack(frames: [frame2], modules: [module2]);
        final stack3 = NativeStack(frames: [frame3], modules: [module3]);
        final buffer =
            RingBuffer<NativeStack>(3)
              ..write(stack1)
              ..write(stack2)
              ..write(stack3);

        final timestampRange = <int>[now - 1000, now];
        final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
          config,
          buffer,
          timestampRange,
        );
        expect(aggregatedNativeFrames.length, 3);
        expect(aggregatedNativeFrames[0].frame, frame3);
        expect(aggregatedNativeFrames[0].occurTimes, 1);
        expect(aggregatedNativeFrames[1].frame, frame2);
        expect(aggregatedNativeFrames[1].occurTimes, 1);
        expect(aggregatedNativeFrames[2].frame, frame1);
        expect(aggregatedNativeFrames[2].occurTimes, 1);
      });

      test('return aggregated frames with multiple frames in stack', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 1,
          sampleRateInMilliseconds: 1000,
        );
        samplerProcessor = SamplerProcessor(config, stackCapturer);
        final now = Timeline.now;
        final module = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(pc: 1, timestamp: now - 100, module: module);
        final frame2 = NativeFrame(pc: 2, timestamp: now - 200, module: module);
        final frame3 = NativeFrame(pc: 3, timestamp: now - 300, module: module);
        final frame4 = NativeFrame(pc: 4, timestamp: now - 400, module: module);
        final frame5 = NativeFrame(pc: 5, timestamp: now - 500, module: module);

        final stack1 = NativeStack(
          frames: [frame1, frame2, frame3],
          modules: [module, module, module],
        );
        final stack2 = NativeStack(
          frames: [frame4, frame5],
          modules: [module, module],
        );
        final buffer =
            RingBuffer<NativeStack>(3)
              ..write(stack1)
              ..write(stack2);

        final timestampRange = <int>[now - 10000, now];
        final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
          config,
          buffer,
          timestampRange,
        );
        expect(aggregatedNativeFrames.length, 5);
        expect(
          aggregatedNativeFrames.map((e) => e.frame).toList(),
          equals([frame4, frame5, frame1, frame2, frame3]),
        );
        for (final frame in aggregatedNativeFrames) {
          expect(frame.occurTimes, 1);
        }
      });

      test(
        'return aggregated frames with multiple frames with duplicate frames in stack',
        () {
          stackCapturer = FakeStackCapturer();
          final config = SamplerConfig(
            jankThreshold: 1,
            sampleRateInMilliseconds: 1000,
          );
          samplerProcessor = SamplerProcessor(config, stackCapturer);
          final now = Timeline.now;
          final module = NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          );
          final frame1 = NativeFrame(
            pc: 1,
            timestamp: now - 100,
            module: module,
          );
          final frame2 = NativeFrame(
            pc: 2,
            timestamp: now - 200,
            module: module,
          );
          final frame3 = NativeFrame(
            pc: 3,
            timestamp: now - 300,
            module: module,
          );
          final frame4 = NativeFrame(
            pc: 4,
            timestamp: now - 400,
            module: module,
          );
          final frame5 = NativeFrame(
            pc: 4,
            timestamp: now - 500,
            module: module,
          );

          final stack1 = NativeStack(
            frames: [frame1, frame2, frame3],
            modules: [module, module, module],
          );
          final stack2 = NativeStack(
            frames: [frame4, frame5],
            modules: [module, module],
          );
          final buffer =
              RingBuffer<NativeStack>(3)
                ..write(stack1)
                ..write(stack2);

          final timestampRange = <int>[now - 10000, now];
          final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
            config,
            buffer,
            timestampRange,
          );
          expect(aggregatedNativeFrames.length, 4);
          expect(
            aggregatedNativeFrames.map((e) => e.frame).toList(),
            equals([frame4, frame1, frame2, frame3]),
          );
          expect(aggregatedNativeFrames[0].occurTimes, 2);
        },
      );

      test('return frames between the timestampRange', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 1,
          sampleRateInMilliseconds: 1000,
        );
        samplerProcessor = SamplerProcessor(config, stackCapturer);
        final now = Timeline.now;
        final module1 = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(
          pc: 540642472602,
          timestamp: now - 5000,
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
          timestamp: now - 4000,
          module: module2,
        );
        final module3 = NativeModule(
          id: 3,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'helloworld',
        );
        final frame3 = NativeFrame(
          pc: 540642472605,
          timestamp: now - 3000,
          module: module3,
        );

        final stack1 = NativeStack(frames: [frame1], modules: [module1]);
        final stack2 = NativeStack(frames: [frame2], modules: [module2]);
        final stack3 = NativeStack(frames: [frame3], modules: [module3]);
        final buffer =
            RingBuffer<NativeStack>(3)
              ..write(stack1)
              ..write(stack2)
              ..write(stack3);

        final timestampRange = <int>[now - 3500, now];
        final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
          config,
          buffer,
          timestampRange,
        );
        expect(aggregatedNativeFrames.length, 1);
        expect(aggregatedNativeFrames[0].frame, frame3);
        expect(aggregatedNativeFrames[0].occurTimes, 1);
      });

      test(
        'return aggregated frames greater than jankThreshold with multiple frames with duplicate frames in stack',
        () {
          stackCapturer = FakeStackCapturer();
          final config = SamplerConfig(
            jankThreshold: 2,
            sampleRateInMilliseconds: 1,
          );
          samplerProcessor = SamplerProcessor(config, stackCapturer);
          final now = Timeline.now;
          final module = NativeModule(
            id: 1,
            path: 'libapp.so',
            baseAddress: 540641718272,
            symbolName: 'hello',
          );
          final frame1 = NativeFrame(
            pc: 1,
            timestamp: now - 100,
            module: module,
          );
          final frame2 = NativeFrame(
            pc: 2,
            timestamp: now - 200,
            module: module,
          );
          final frame3 = NativeFrame(
            pc: 2,
            timestamp: now - 300,
            module: module,
          );
          final frame4 = NativeFrame(
            pc: 2,
            timestamp: now - 400,
            module: module,
          );
          final frame5 = NativeFrame(
            pc: 3,
            timestamp: now - 500,
            module: module,
          );

          final stack1 = NativeStack(
            frames: [frame1, frame2, frame3, frame4],
            modules: [module, module, module],
          );
          final stack2 = NativeStack(frames: [frame5], modules: [module]);
          final buffer =
              RingBuffer<NativeStack>(3)
                ..write(stack1)
                ..write(stack2);

          final timestampRange = <int>[now - 10000, now];
          final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
            config,
            buffer,
            timestampRange,
          );
          expect(aggregatedNativeFrames.length, 1);
          expect(
            aggregatedNativeFrames.map((e) => e.frame).toList(),
            equals([frame2]),
          );
          expect(aggregatedNativeFrames[0].occurTimes, 3);
        },
      );

      test('return empty if no frames greater than jankThreshold', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 10,
          sampleRateInMilliseconds: 1,
        );
        samplerProcessor = SamplerProcessor(config, stackCapturer);
        final now = Timeline.now;
        final module1 = NativeModule(
          id: 1,
          path: 'libapp.so',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final frame1 = NativeFrame(
          pc: 540642472602,
          timestamp: now - 5000,
          module: module1,
        );

        final stack1 = NativeStack(frames: [frame1], modules: [module1]);

        final buffer = RingBuffer<NativeStack>(3)..write(stack1);

        final timestampRange = <int>[now - 10000, now];
        final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
          config,
          buffer,
          timestampRange,
        );
        expect(aggregatedNativeFrames.length, 0);
      });

      test('only return frames with max length kMaxStackTraces', () {
        stackCapturer = FakeStackCapturer();
        final config = SamplerConfig(
          jankThreshold: 1,
          sampleRateInMilliseconds: 1000,
        );
        samplerProcessor = SamplerProcessor(config, stackCapturer);
        final now = Timeline.now;
        final module = NativeModule(
          id: 1,
          path: 'Runner.app/Frameworks/App.framework/App',
          baseAddress: 540641718272,
          symbolName: 'hello',
        );
        final buffer = RingBuffer<NativeStack>(200);

        for (int i = 0; i < 200; ++i) {
          final frame = NativeFrame(pc: i, timestamp: now - i, module: module);
          buffer.write(NativeStack(frames: [frame], modules: [module]));
        }

        final timestampRange = <int>[now - 10000, now];
        final aggregatedNativeFrames = SamplerProcessor.aggregateStacks(
          config,
          buffer,
          timestampRange,
        );
        expect(aggregatedNativeFrames.length, kMaxStackTraces);
      });
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
      expect(buffer.readAllReversed(), equals([2, 1]));
    });

    test('readAll after full', () {
      final buffer = RingBuffer<int>(2);
      buffer.write(1);
      buffer.write(2);
      buffer.write(3);
      expect(buffer.readAllReversed(), equals([3, 2]));
    });
  });
}
