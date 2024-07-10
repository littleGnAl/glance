import 'dart:developer';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:ffi/src/utf8.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glance/src/collect_stack.dart';

class FakeCollectStackNativeBindings implements CollectStackNativeBindings {
  FakeCollectStackNativeBindings(this.arena);

  final Arena arena;

  bool isCollectStackTraceOfTargetThread = false;
  bool isDladdr = false;
  bool isLookupSymbolName = false;
  bool isSetCurrentThreadAsTarget = false;

  @override
  // ignore: non_constant_identifier_names
  ffi.Pointer<Utf8> CollectStackTraceOfTargetThread(
      ffi.Pointer<ffi.Int64> buf, int bufSize) {
    isCollectStackTraceOfTargetThread = true;
    buf[0] = 123;
    return ffi.nullptr; // success
  }

  @override
  // ignore: non_constant_identifier_names
  int Dladdr(ffi.Pointer<ffi.Void> addr, ffi.Pointer<DlInfo> info) {
    isDladdr = true;
    info.ref.fileName = "libapp.so".toNativeUtf8(allocator: arena);
    info.ref.baseAddress = ffi.Pointer<ffi.Void>.fromAddress(123);
    info.ref.symbolName = "hello".toNativeUtf8(allocator: arena);
    info.ref.symbolAddress = ffi.Pointer<ffi.Void>.fromAddress(456);

    return 1; // found
  }

  @override
  // ignore: non_constant_identifier_names
  ffi.Pointer<Utf8> LookupSymbolName(ffi.Pointer<DlInfo> info) {
    isLookupSymbolName = true;
    // Do not use the `arena` to allocate it, since it will be freed by the user
    return "hello".toNativeUtf8();
  }

  @override
  // ignore: non_constant_identifier_names
  void SetCurrentThreadAsTarget() {
    isSetCurrentThreadAsTarget = true;
  }
}

void main() {
  late FakeCollectStackNativeBindings nativeBindings;
  late StackCapturer stackCapturer;

  group('StackCapturer', () {
    test('setCurrentThreadAsTarget', () {
      using((arena) {
        nativeBindings = FakeCollectStackNativeBindings(arena);
        stackCapturer = StackCapturer(nativeBindings: nativeBindings);

        stackCapturer.setCurrentThreadAsTarget();
        expect(nativeBindings.isSetCurrentThreadAsTarget, isTrue);
      });
    });

    test('captureStackOfTargetThread', () {
      using((arena) {
        nativeBindings = FakeCollectStackNativeBindings(arena);
        stackCapturer = StackCapturer(nativeBindings: nativeBindings);

        final nativeStack = stackCapturer.captureStackOfTargetThread();
        expect(nativeBindings.isCollectStackTraceOfTargetThread, isTrue);
        expect(nativeBindings.isDladdr, isTrue);
        expect(nativeBindings.isLookupSymbolName, isTrue);

        final frame = nativeStack.frames[0];
        final module = nativeStack.modules[0];
        expect(frame.pc, 123);
        expect(frame.module, module);
        expect(frame.module, module);

        expect(module.id, 0); // The first `id` is 0
        expect(module.path, 'libapp.so');
        expect(module.baseAddress, 123);
        expect(module.symbolName, 'hello');
      });
    });
  });
}
