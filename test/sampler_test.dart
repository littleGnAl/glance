import 'dart:developer';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:glance/src/collect_stack.dart';
import 'package:glance/src/sampler.dart';

class TestSamplerProcessorResult {
  List<AggregatedNativeFrame> frames = [];
  bool isLoop = false;
  bool isSetCurrentThreadAsTarget = false;
}

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

  TestSamplerProcessorResult result = TestSamplerProcessorResult();

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

void main() {
  late FakeSamplerProcessor processor;
  late Sampler sampler;

  setUp(() async {
    // processor = FakeSamplerProcessor();
  });

  group('Sampler', () {
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
  });
}
