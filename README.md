# glance

An APM library for detecting UI jank in Flutter for mobile (Android/iOS).

**NOTE:** This package is experimental. APIs may change without notice before the stable version 1.0.

`glance` detects UI jank during the build phase and from "external sources", such as `WidgetBindingObserver` callbacks, touch events, and method channel callbacks. These cover most cases that cause UI jank. It works only when you build your application with the `--split-debug-info` option, see https://docs.flutter.dev/deployment/obfuscate#obfuscate-your-app for more detail. 

Run `glance` in release or profile build, as detecting UI jank in debug mode is not meaningful.

## Getting Started

### Start UI Jank Detection

> `glance` works only when you build your application with the `--split-debug-info` option, see https://docs.flutter.dev/deployment/obfuscate#obfuscate-your-app for more detail. 

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

### Symbolize the jank stack traces

After obtaining the glance stack traces, you can use the `flutter symbolize` command to symbolize them. For more details, see [Flutter documentation](https://docs.flutter.dev/deployment/obfuscate#read-an-obfuscated-stack-trace)

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
