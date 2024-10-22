# glance

An APM library for detecting UI jank in Flutter for mobile (Android/iOS).

**NOTE:** This package is experimental. APIs may change without notice before the stable version 1.0.

Building smooth APPs with Flutter is easy, but as your APP grows in complexity and faces a variety of user environments and devices, ensuring smooth performance in production can be challenging. Even if your app runs smoothly locally, it doesn't guarantee the same for all users. `glance` helps collect stack traces during UI jank, allowing you to pinpoint the exact function causing the performance issue, so you can resolve it effectively.

`glance` detects UI jank during the rendering as well as through various callbacks, such as, `WidgetBindingObserver` callbacks, touch events, and method channel callbacks. These cover most cases that cause UI jank. It works only in release or profile builds when your application is built with the [`--split-debug-info` option](https://docs.flutter.dev/deployment/obfuscate#obfuscate-your-app). 

## Getting Started

### Start UI Jank Detection

To receive UI jank information, implement your own reporter (`JankDetectedReporter`). Once you have the jank information, you can save the stack traces to a file, or upload them to your server, and symbolize them using the `flutter symbolize` command.

```dart
// Implement your `JankDetectedReporter`
class MyJankDetectedReporter extends JankDetectedReporter {
  @override
  void report(JankReport info) {
    final stackTrace = info.stackTrace.toString();
    // Save the stack traces to a file, or upload them to your server,
    // symbolize them using the `flutter symbolize` command.
  }
}

void main() {
  // Call `GlanceWidgetBinding.ensureInitialized()` first
  GlanceWidgetBinding.ensureInitialized();
  // Start UI Jank Detection
  Glance.instance.start(config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));

  runApp(const MyApp());
}
```

`glance` works only when you build your application with the `--split-debug-info` option (see [Flutter documentation](https://docs.flutter.dev/deployment/obfuscate#obfuscate-your-app)). For example, to build an Android APK:

```
flutter build apk --release --split-debug-info=debug-info
```

### Symbolize the jank stack traces

After obtaining the glance stack traces, you can use the `flutter symbolize` command (see [Flutter documentation](https://docs.flutter.dev/deployment/obfuscate#read-an-obfuscated-stack-trace)) to symbolize them. 

For example, assume you get the stack traces from `info.stackTrace.toString()` in the above code on Android and save them to `my_stacktraces.txt` file:

```
// my_stacktraces.txt

*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 32542, tid: 32575, name 1.ui
os: android arch: arm64 comp: yes sim: no
build_id: '4dbecf547733e72ae1688d73ebb5f062'
isolate_dso_base: 7de0e44000, vm_dso_base: 7de0e44000
isolate_instructions: 7de0efa840, vm_instructions: 7de0ee4000
    #00 abs 0000007de0f63ae8 _kDartIsolateSnapshotInstructions+0x692a8
    #01 abs 0000007de0f63a04 _kDartIsolateSnapshotInstructions+0x691c4
    #02 abs 0000007de0fed7a8 _kDartIsolateSnapshotInstructions+0xf2f68
    #03 abs 0000007de10611b0 _kDartIsolateSnapshotInstructions+0x166970
    #04 abs 0000007de0facecc _kDartIsolateSnapshotInstructions+0xb268c
    #05 abs 0000007de106b3a0 _kDartIsolateSnapshotInstructions+0x170b60
    #06 abs 0000007de1023900 _kDartIsolateSnapshotInstructions+0x1290c0
    #07 abs 0000007de102320c _kDartIsolateSnapshotInstructions+0x1289cc
    #08 abs 0000007de10231d0 _kDartIsolateSnapshotInstructions+0x128990
    #09 abs 0000007de106c248 _kDartIsolateSnapshotInstructions+0x171a08
    #10 abs 0000007de106bfd4 _kDartIsolateSnapshotInstructions+0x171794

```

After running the `flutter symbolize` command:

```
flutter symbolize -i my_stacktraces.txt -d debug-info/app.android-arm64.symbols
```

You can get the symbolized stack traces like this:

```
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 32542, tid: 32575, name 1.ui
os: android arch: arm64 comp: yes sim: no
build_id: '4dbecf547733e72ae1688d73ebb5f062'
isolate_dso_base: 7de0e44000, vm_dso_base: 7de0e44000
isolate_instructions: 7de0efa840, vm_instructions: 7de0ee4000
#0      jsonEncode (third_party/dart/sdk/lib/convert/json.dart:114:10)
#1      expensiveFunction (/my/project/jank_app.dart:22:5)
#2      _BuildPhaseJankWidgetState.build (/my/project/build_phase_jank_test.dart:26:3)
#3      StatefulElement.build (/my/path/flutter/packages/flutter/lib/src/widgets/framework.dart:5592:3)
#4      Element.widget (/my/path/flutter/packages/flutter/lib/src/widgets/framework.dart)
#5      ComponentElement.performRebuild (/my/path/flutter/packages/flutter/lib/src/widgets/framework.dart:5486:31)
#6      StatefulElement.performRebuild (/my/path/flutter/packages/flutter/lib/src/widgets/framework.dart:5638:3)
#7      List.iterator (third_party/dart/sdk/lib/_internal/vm/lib/growable_array.dart:507:16)
#8      BuildOwner.buildScope (/my/path/flutter/packages/flutter/lib/src/widgets/framework.dart:2952:37)
#9      WidgetsBinding.drawFrame (/my/path/flutter/packages/flutter/lib/src/widgets/binding.dart:1230:13)
#10     RendererBinding._handlePersistentFrameCallback (/my/path/flutter/packages/flutter/lib/src/rendering/binding.dart:469:5)
```

### Symbolize Automatically
Some tools, like Firebase and Sentry, can automatically symbolize the stack traces if you upload the symbols. This is helpful if you do not have a self-hosted server.
See more detail:
- Firebase: https://firebase.google.com/docs/crashlytics/get-deobfuscated-reports?platform=flutter
- Sentry: https://docs.sentry.io/platforms/flutter/upload-debug/

## Acknowledgements

Thanks to [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example) for the inspiration, which made this project possible.

## License

Some files in this project are licensed under the BSD 3-Clause "New" or "Revised" License from [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example). See the `LICENSE-original` file for details.

The rest of the project is licensed under the MIT License. See the `LICENSE` file for details.
