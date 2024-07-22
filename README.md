# glance
> This library is still under heavy development, the APIs will be changed without notice before it come to stable(1.0).
> feel free to try it, but it's not recommand to use in production at this time.

An APM(Application Performance Monitoring) library for UI jank detection for Flutter.

## Getting Started
### Start the UI jank detection
```dart
// Implement your `JankDetectedReporter`
class MyJankDetectedReporter extends JankDetectedReporter {
  @override
  void report(JankReport info) {
    final stackTrace = info.stackTrace.toString();
    // Save the stack traces to the file, or upload the stack traces to your server.
    // You should symbolize the stack traces
  }
}

// Start the UI jank detection
Glance.instance.start(config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));

```

### Symbolize the glance stack traces
After you get the glance stack traces, you should use the built-in tool to symbolize the stack traces.

Install llvm

```
dart pub global activate glance
glance --symbol-file=<symbol-file-path> --stack-traces-file=<stack-traces-file-path> --out=<symbolized-output-file-path>
```
symbol-file: The symbol file path of `--split-debug`
stack-traces-file: The stack traces got from the `GlanceStackTrace.toString()` function.
out: The symbolized output file path


## Acknowledgements
Thanks to [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example) for the inspiration, which made this project possible.


## License
Some files in this project are licensed under the BSD 3-Clause "New" or "Revised" License from [thread_collect_stack_example](https://github.com/mraleph/thread_collect_stack_example). See the `LICENSE-original` file for details.

The rest of the project is licensed under the MIT License. See the `LICENSE` file for details.


