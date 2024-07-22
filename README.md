# glance

> This library is still under heavy development. APIs may change without notice before it reaches stable version 1.0. Feel free to try it, but it is not recommended for production use at this time.

An APM (Application Performance Monitoring) library for detecting UI jank in Flutter.

## Getting Started

### Start UI Jank Detection
```dart
// Implement your `JankDetectedReporter`
class MyJankDetectedReporter extends JankDetectedReporter {
  @override
  void report(JankReport info) {
    final stackTrace = info.stackTrace.toString();
    // Save the stack traces to a file, or upload them to your server.
    // After getting the stack traces, you can symbolize them using the built-in tool. See details below.
  }
}

// Start UI Jank Detection
Glance.instance.start(config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));
```

### Symbolize the glance stack traces
After you get the glance stack traces, you should use the built-in tool to symbolize the stack traces.

> Before you run the tool, ensure you install llvm first.

```
dart pub global activate glance
glance --symbol-file=<symbol-file-path> --stack-traces-file=<stack-traces-file-path> --out=<symbolized-output-file-path>
```
- `symbol-file`: The path to the symbols file generated by the `--split-debug-info` option of the Flutter command. See [Flutter documentation](https://docs.flutter.dev/deployment/obfuscate#obfuscate-your-app) for more details.
- `stack-traces-file`: The stack traces obtained from the `GlanceStackTrace.toString()` function.
- out: The path for the symbolized output file.


## Acknowledgements
Thanks to [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example) for the inspiration, which made this project possible.


## License
Some files in this project are licensed under the BSD 3-Clause "New" or "Revised" License from [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example). See the `LICENSE-original` file for details.

The rest of the project is licensed under the MIT License. See the `LICENSE` file for details.


