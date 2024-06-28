import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:glance/glance.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class MyJankDetectedReporter extends JankDetectedReporter {
  @override
  void report(JankReport info) {
    compute((msg) async {
      final (token, info) = msg;
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

      final docDir = await getExternalStorageDirectory();
      final stacktraceFilePath = path.join(
        docDir!.absolute.path,
        'jank_trace',
        'jank_trace_${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      print('addJankCallback stacktraceFilePath: ${stacktraceFilePath}');
      final file = File(stacktraceFilePath);
      file.createSync(recursive: true);
      File(stacktraceFilePath).writeAsStringSync(
        info.stackTrace.toString(),
        flush: true,
      );
    }, (RootIsolateToken.instance, info));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _startGlance();
  runApp(const MyApp());
}

Future<void> _startGlance() async {
  // WidgetsFlutterBinding.ensureInitialized();
  Glance.instance.start(
      config: GlanceConfiguration(reporters: [MyJankDetectedReporter()]));

  await Permission.storage.request();

  // Glance.instance.addJankCallback((info) async {
  //   compute((msg) async {
  //     final (token, info) = msg;
  //     BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

  //     final docDir = await getExternalStorageDirectory();
  //     final stacktraceFilePath = path.join(
  //       docDir!.absolute.path,
  //       'jank_trace',
  //       'jank_trace_${DateTime.now().microsecondsSinceEpoch}.json',
  //     );
  //     print('addJankCallback stacktraceFilePath: ${stacktraceFilePath}');
  //     final file = File(stacktraceFilePath);
  //     file.createSync(recursive: true);
  //     File(stacktraceFilePath).writeAsStringSync(
  //       jsonEncode(info.toJson()),
  //       flush: true,
  //     );
  //   }, (RootIsolateToken.instance, info));
  // });

  // Glance.instance.addSlowFunctionsDetectedCallback((info) {
  //   compute((msg) async {
  //     final (token, info) = msg;
  //     BackgroundIsolateBinaryMessenger.ensureInitialized(token!);

  //     final docDir = await getExternalStorageDirectory();
  //     final stacktraceFilePath = path.join(
  //       docDir!.absolute.path,
  //       'jank_trace',
  //       'jank_trace_${DateTime.now().microsecondsSinceEpoch}.json',
  //     );
  //     print(
  //         'SlowFunctionsDetectedCallback stacktraceFilePath: ${stacktraceFilePath}');
  //     final file = File(stacktraceFilePath);
  //     file.createSync(recursive: true);
  //     File(stacktraceFilePath).writeAsStringSync(
  //       jsonEncode(info.toJson()),
  //       flush: true,
  //     );
  //   }, (RootIsolateToken.instance, info));
  // });
  // Glance.instance.start();
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      showPerformanceOverlay: true,
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    final watch = Stopwatch();
    watch.start();
    for (int i = 0; i < 1000; ++i) {
      jsonEncode({
        for (int i = 0; i < 10000; ++i) 'aaa': 0,
      });
    }
    Timeline.now;
    watch.stop();
    print('_incrementCounter time spend: ${watch.elapsedMilliseconds}');
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text('$_counter'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
