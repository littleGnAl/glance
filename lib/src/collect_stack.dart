// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

import 'dart:developer';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

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

class NativeFrame {
  final NativeModule? module;
  final int pc;
  final int timestamp;
  NativeFrame({
    this.module,
    required this.pc,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is NativeFrame &&
        module == other.module &&
        pc == other.pc &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode => Object.hash(module, pc, timestamp);
}

class NativeModule {
  final int id;
  final String path;
  final int baseAddress;
  final String symbolName;
  NativeModule(
      {required this.id,
      required this.path,
      required this.baseAddress,
      required this.symbolName});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    return other is NativeModule &&
        id == other.id &&
        path == other.path &&
        baseAddress == other.baseAddress &&
        symbolName == other.symbolName;
  }

  @override
  int get hashCode => Object.hash(id, path, baseAddress, symbolName);
}

class NativeStack {
  final List<NativeFrame> frames;
  final List<NativeModule> modules;
  NativeStack({required this.frames, required this.modules});
}

ffi.DynamicLibrary _loadLib() {
  const libName = 'glance';
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$libName.dll');
  }

  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('lib$libName.so');
  }

  return ffi.DynamicLibrary.process();
}

class StackCapturer {
  StackCapturer({CollectStackNativeBindings? nativeBindings})
      : _nativeBindings =
            nativeBindings ?? CollectStackNativeBindings(_loadLib());

  final CollectStackNativeBindings _nativeBindings;

  void setCurrentThreadAsTarget() {
    _nativeBindings.SetCurrentThreadAsTarget();
  }

  /// Refer to the implementation from Flutter Engine, we should use the `Timeline.now` as the current timestamp.
  /// https://github.com/flutter/engine/blob/5d97d2bcdffc8b21bc0b9742f1136583f4cc8e16/runtime/dart_timestamp_provider.cc#L24
  int _nowInMicrosSinceEpoch() {
    return Timeline.now;
  }

  NativeStack captureStackOfTargetThread() {
    return using((arena) {
      const maxStackDepth = 1024;
      final outputBuffer =
          arena.allocate<ffi.Int64>(ffi.sizeOf<ffi.Int64>() * maxStackDepth);
      final error = _nativeBindings.CollectStackTraceOfTargetThread(
          outputBuffer, maxStackDepth);
      if (error != ffi.nullptr) {
        final errorString = error.toDartString();
        malloc.free(error);
        print('errorString: $errorString');
        return NativeStack(
            frames: [],
            modules: []); // Something went wrong. but just discard info this time.
      }

      final dlInfo = arena.allocate<DlInfo>(ffi.sizeOf<DlInfo>());

      // Process stack trace: which is a sequence of hexadecimal numbers
      // separated by commas. For each frame try to locate base address
      // of the module it belongs to using |dladdr|.
      final modules = <String, NativeModule>{};
      final frames = outputBuffer
          .asTypedList(maxStackDepth)
          .takeWhile((value) => value != 0)
          .map((addr) {
        final found = _nativeBindings.Dladdr(
            ffi.Pointer<ffi.Void>.fromAddress(addr), dlInfo);
        if (found == 0) {
          return NativeFrame(
            pc: addr,
            timestamp: _nowInMicrosSinceEpoch(),
          );
        }

        final sn = _nativeBindings.LookupSymbolName(dlInfo);
        final symbolName = sn != ffi.nullptr ? sn.toDartString() : '';
        malloc.free(sn);

        final modulePath = dlInfo.ref.fileName.toDartString();
        final module = modules[modulePath] ??= NativeModule(
          id: modules.length,
          path: modulePath,
          baseAddress: dlInfo.ref.baseAddress.address,
          symbolName: symbolName,
        );

        return NativeFrame(
          module: module,
          pc: addr,
          timestamp: _nowInMicrosSinceEpoch(),
        );
      }).toList(growable: false);

      return NativeStack(
          frames: frames, modules: modules.values.toList(growable: false));
    });
  }
}
