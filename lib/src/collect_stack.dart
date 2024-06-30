// Original BSD 3-Clause License
// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE-original file.

// Modifications and new contributions
// Copyright (c) 2024 Littlegnal. Licensed under the MIT License. See the LICENSE file for details.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:glance/src/collect_stack_native_bindings.dart';

class NativeFrame {
  final NativeModule? module;
  final int pc;
  final int timestamp;
  NativeFrame({
    this.module,
    required this.pc,
    required this.timestamp,
  });
}

class NativeFrameTimeSpent {
  final NativeFrame frame;
  int timestampInMacros = 0;
  NativeFrameTimeSpent(this.frame);

  // set timestampInMacros(int value) {
  //   _timestampInMacros = value;
  // }
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
}

class NativeStack {
  final List<NativeFrame> frames;
  final List<NativeModule> modules;
  NativeStack({required this.frames, required this.modules});
}

class RingBuffer<T> {
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

class SlowFunctionsInformation {
  const SlowFunctionsInformation({
    required this.stackTraces,
    required this.jankDuration,
  });
  final List<NativeFrameTimeSpent> stackTraces;
  final Duration jankDuration;

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  // JankInformation fromJson(Map<String, Object?> json) {

  // }

  Map<String, Object?> toJson() {
    return {
      'jankDuration': jankDuration.inMilliseconds,
      'stackTraces': stackTraces.map((frameTimeSpent) {
        final frame = frameTimeSpent.frame;
        final spent = frameTimeSpent.timestampInMacros;
        return {
          "pc": frame.pc.toString(),
          "timestamp": frame.timestamp,
          if (frame.module != null)
            "baseAddress": frame.module!.baseAddress.toString(),
          if (frame.module != null) "path": frame.module!.path,
          'spent': spent,
        };
      }).toList()
    };
  }
}

typedef SlowFunctionsDetectedCallback = void Function(
    SlowFunctionsInformation info);

ffi.DynamicLibrary _loadLib() {
  const _libName = 'glance';
  if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('$_libName.dll');
  }

  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('lib$_libName.so');
  }

  return ffi.DynamicLibrary.process();
}

class StackCollector {
  StackCollector() : _nativeBindings = CollectStackNativeBindings(_loadLib());

  final CollectStackNativeBindings _nativeBindings;

  void setCurrentThreadAsTarget() {
    // final binding = CollectStackNativeBindings(_loadLib());
    _nativeBindings.SetCurrentThreadAsTarget();
  }

  /// Refer to the implementation of Flutter Engine, we should use the `Timeline.now` as the current timestamp.
  /// https://github.com/flutter/engine/blob/5d97d2bcdffc8b21bc0b9742f1136583f4cc8e16/runtime/dart_timestamp_provider.cc#L24
  int _nowInMicrosSinceEpoch() {
    return Timeline.now;
  }

  NativeStack captureStackOfTargetThread() {
    return using((arena) {
      // Invoke CollectStackTrace from helper library.
      const maxStackDepth = 1024;
      final outputBuffer =
          arena.allocate<ffi.Int64>(ffi.sizeOf<ffi.Int64>() * maxStackDepth);
      final error = _nativeBindings.CollectStackTraceOfTargetThread(
          outputBuffer, maxStackDepth);
      if (error != ffi.nullptr) {
        final errorString = error.toDartString();
        malloc.free(error);
        print('errorString: $errorString');
        return NativeStack(frames: [], modules: []);
        // throw StateError(errorString); // Something went wrong. but just discard info this time.
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
            timestamp:
                _nowInMicrosSinceEpoch(), // DateTime.now().millisecondsSinceEpoch,
          );
        }

        // if (dlInfo.ref.symbolName != ffi.nullptr) {
        //   print(
        //       'dlInfo.ref.symbolName: ${dlInfo.ref.symbolName.toDartString()}');
        // }

        final sn = _nativeBindings.LookupSymbolName(dlInfo);
        // if (sn != ffi.nullptr) {
        //   print('sn: ${sn.toDartString()}');
        // }
        // if (dlInfo.ref.fileName != ffi.nullptr) {
        //   print('dlInfo.ref.fileName: ${dlInfo.ref.fileName.toDartString()}');
        // }

        final modulePath = dlInfo.ref.fileName.toDartString();
        final module = modules[modulePath] ??= NativeModule(
          id: modules.length,
          path: modulePath,
          baseAddress: dlInfo.ref.baseAddress.address,
          symbolName: sn != ffi.nullptr ? sn.toDartString() : '',
        );

        return NativeFrame(
          module: module,
          pc: addr,

          timestamp:
              _nowInMicrosSinceEpoch(), // DateTime.now().millisecondsSinceEpoch,
        );
      }).toList(growable: false);

      return NativeStack(
          frames: frames, modules: modules.values.toList(growable: false));
    });
  }
}
