import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:ffi/src/utf8.dart';
import 'package:glance/src/collect_stack.dart';

class FakeCollectStackNativeBindings implements CollectStackNativeBindings {
  @override
  // ignore: non_constant_identifier_names
  ffi.Pointer<Utf8> CollectStackTraceOfTargetThread(
      ffi.Pointer<ffi.Int64> buf, int bufSize) {
    // TODO: implement CollectStackTraceOfTargetThread
    throw UnimplementedError();
  }

  @override
  int Dladdr(ffi.Pointer<ffi.Void> addr, ffi.Pointer<DlInfo> info) {
    // TODO: implement Dladdr
    throw UnimplementedError();
  }

  @override
  ffi.Pointer<Utf8> LookupSymbolName(ffi.Pointer<DlInfo> info) {
    // TODO: implement LookupSymbolName
    throw UnimplementedError();
  }

  @override
  void SetCurrentThreadAsTarget() {
    // TODO: implement SetCurrentThreadAsTarget
  }
}

void main() {}
