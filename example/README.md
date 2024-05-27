# glance_example

Demonstrates how to use the glance plugin.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


adb -d shell "run-as com.littlegnal.glance_example cat /storage/emulated/0/Android/data/com.littlegnal.glance_example/files/jank_trace/jank_trace_1718391992447737.json" > jank_trace_1718391992447737.json

dart run /Users/littlegnal/codes/personal-project/glance_plugin/glance/bin/symbolize.dart --symbol-file=/Users/littlegnal/codes/personal-project/glance_plugin/glance/example/debug-info/app.android-arm64.symbols --stack-trace-file=/Users/littlegnal/codes/personal-project/glance_plugin/glance/example/jank_trace_1718397490839577.json > desymbol.txt
