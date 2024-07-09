import 'dart:ffi';

import 'package:ffi/src/utf8.dart';
import 'package:glance/src/collect_stack.dart';

class FakeCollectStackNativeBindings implements CollectStackNativeBindings {
  @override
  // ignore: non_constant_identifier_names
  Pointer<Utf8> CollectStackTraceOfTargetThread(
      Pointer<Int64> buf, int bufSize) {
    // TODO: implement CollectStackTraceOfTargetThread
    throw UnimplementedError();
  }

  @override
  int Dladdr(Pointer<Void> addr, Pointer<DlInfo> info) {
    // TODO: implement Dladdr
    throw UnimplementedError();
  }

  @override
  Pointer<Utf8> LookupSymbolName(Pointer<DlInfo> info) {
    // TODO: implement LookupSymbolName
    throw UnimplementedError();
  }

  @override
  void SetCurrentThreadAsTarget() {
    // TODO: implement SetCurrentThreadAsTarget
  }
}

void main() {}
