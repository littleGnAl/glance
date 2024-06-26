// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

// import 'glance_internal.dart' ;

/// Dl_info from dlfcn.h.
///
/// See `man dladdr`.
final class DlInfo extends ffi.Struct {
  external ffi.Pointer<Utf8> fileName;
  external ffi.Pointer<ffi.Void> baseAddress;
  external ffi.Pointer<Utf8> symbolName;
  external ffi.Pointer<ffi.Void> symbolAddress;
}

/// Bindings to `collect_stack.cc`
class CollectStackNativeBindings {
  /// Holds the symbol lookup function.
  final ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
      _lookup;

  /// The symbols are looked up in [dynamicLibrary].
  CollectStackNativeBindings(ffi.DynamicLibrary dynamicLibrary)
      : _lookup = dynamicLibrary.lookup;

  /// The symbols are looked up with [lookup].
  CollectStackNativeBindings.fromLookup(
      ffi.Pointer<T> Function<T extends ffi.NativeType>(String symbolName)
          lookup)
      : _lookup = lookup;

  void SetCurrentThreadAsTarget() {
    return _SetCurrentThreadAsTarget();
  }

  late final _SetCurrentThreadAsTargetPtr =
      _lookup<ffi.NativeFunction<ffi.Void Function()>>(
          'SetCurrentThreadAsTarget');
  late final _SetCurrentThreadAsTarget =
      _SetCurrentThreadAsTargetPtr.asFunction<void Function()>();

  // @Native<Void Function()>(symbol: 'SetCurrentThreadAsTarget')
  // external void setCurrentThreadAsTarget();

  ffi.Pointer<Utf8> CollectStackTraceOfTargetThread(
    ffi.Pointer<ffi.Int64> buf,
    int bufSize,
  ) {
    return _CollectStackTraceOfTargetThread(buf, bufSize);
  }

  late final _CollectStackTraceOfTargetThreadPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Int64>,
              ffi.Size)>>('CollectStackTraceOfTargetThread');
  late final _CollectStackTraceOfTargetThread =
      _CollectStackTraceOfTargetThreadPtr.asFunction<
          ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Int64>, int)>();

  /// From collect_stack.cc
  // @Native<Pointer<Utf8> Function(Pointer<Int64>, Size)>(
  //     symbol: 'CollectStackTraceOfTargetThread')
  // external Pointer<Utf8> _collectStackTraceOfTargetThread(
  //     Pointer<Int64> buf, int bufSize);

  ffi.Pointer<ffi.Void> Dlopen(
    ffi.Pointer<Utf8> path,
    int flags,
  ) {
    return _Dlopen(path, flags);
  }

  late final _DlopenPtr = _lookup<
      ffi.NativeFunction<
          ffi.Pointer<ffi.Void> Function(
              ffi.Pointer<Utf8>, ffi.Int)>>('dlopen');
  late final _Dlopen = _DlopenPtr.asFunction<
      ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, int)>();

  /// `void *dlopen(const char *filename, int flags);`
  ///
  /// See `man dlopen`
  // @Native<Pointer<Void> Function(Pointer<Utf8> path, Int)>(symbol: 'dlopen')
  // external Pointer<Void> _dlopen(Pointer<Utf8> path, int flags);

  // LookupSymbolName

  ffi.Pointer<Utf8> LookupSymbolName(
    ffi.Pointer<DlInfo> info,
  ) {
    return _LookupSymbolName(info);
  }

  late final _LookupSymbolNamePtr = _lookup<
          ffi.NativeFunction<ffi.Pointer<Utf8> Function(ffi.Pointer<DlInfo>)>>(
      'LookupSymbolName');
  late final _LookupSymbolName = _LookupSymbolNamePtr.asFunction<
      ffi.Pointer<Utf8> Function(ffi.Pointer<DlInfo>)>();

  // TimestampNowInMicrosSinceEpoch

  int TimestampNowInMicrosSinceEpoch() {
    return _TimestampNowInMicrosSinceEpoch();
  }

  late final _TimestampNowInMicrosSinceEpochPtr =
      _lookup<ffi.NativeFunction<ffi.Int64 Function()>>(
          'TimestampNowInMicrosSinceEpoch');
  late final _TimestampNowInMicrosSinceEpoch =
      _TimestampNowInMicrosSinceEpochPtr.asFunction<int Function()>();

  int Dladdr(
    ffi.Pointer<ffi.Void> addr,
    ffi.Pointer<DlInfo> info,
  ) {
    return _dladdr(addr, info);
  }

  late final _dladdrPtr = _lookup<
      ffi.NativeFunction<
          ffi.Int Function(
              ffi.Pointer<ffi.Void>, ffi.Pointer<DlInfo>)>>('dladdr');
  late final _dladdr = _dladdrPtr
      .asFunction<int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<DlInfo>)>();
}
