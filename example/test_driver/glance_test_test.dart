import 'package:integration_test/common.dart';
import 'package:integration_test/integration_test_driver.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:path/path.dart' as path;
import 'package:file/file.dart' as file;
import 'package:process/process.dart';

import '../../bin/symbolize.dart';

Future<String> _desymbols(
  file.FileSystem fileSystem,
  ProcessManager processManager,
  String stackTraceFileName,
  String stackTrace,
) async {
  final symbolFilePath = path.join('debug-info', 'app.android-arm64.symbols');
  final tmpFilePath = path.join(path.current, 'build',
      'glance_integration_test', '${stackTraceFileName}.tmp');
  // final outputDir = fileSystem.directory(outputDirPath);
  // if (out)
  final tmpFile = fileSystem.file(tmpFilePath);
  await tmpFile.create(recursive: true);
  await tmpFile.writeAsString(stackTrace);

  symbolize(fileSystem, processManager, symbolFilePath!, tmpFilePath);

  String result = '';
  return result;
}

typedef CheckStackTraceCallback = Future<bool> Function(
    String name, String stackTrace);

Future<void> glanceIntegrationDriver({
  FlutterDriver? driver,
  CheckStackTraceCallback? onCheckStackTrace,
  ResponseDataCallback? responseDataCallback = writeResponseData,
  bool writeResponseOnFailure = false,
}) async {
  driver ??= await FlutterDriver.connect();
  // Test states that it's waiting on web driver commands.
  // [DriverTestMessage] is converted to string since json format causes an
  // error if it's used as a message for requestData.
  String jsonResponse =
      await driver.requestData(DriverTestMessage.pending().toString());

  final Map<String, bool> onScreenshotResults = <String, bool>{};

  Response response = Response.fromJson(jsonResponse);

  // Until `integration_test` returns a [WebDriverCommandType.noop], keep
  // executing WebDriver commands.
  // while (response.data != null &&
  //     response.data!['web_driver_command'] != null &&
  //     response.data!['web_driver_command'] != '${WebDriverCommandType.noop}') {
  //   final String? webDriverCommand = response.data!['web_driver_command'] as String?;
  //   if (webDriverCommand == '${WebDriverCommandType.screenshot}') {
  //     assert(onScreenshot != null, 'screenshot command requires an onScreenshot callback');
  //     // Use `driver.screenshot()` method to get a screenshot of the web page.
  //     final List<int> screenshotImage = await driver.screenshot();
  //     final String screenshotName = response.data!['screenshot_name']! as String;
  //     final Map<String, Object?>? args = (response.data!['args'] as Map<String, Object?>?)?.cast<String, Object?>();

  //     final bool screenshotSuccess = await onScreenshot!(screenshotName, screenshotImage, args);
  //     onScreenshotResults[screenshotName] = screenshotSuccess;
  //     if (screenshotSuccess) {
  //       jsonResponse = await driver.requestData(DriverTestMessage.complete().toString());
  //     } else {
  //       jsonResponse =
  //           await driver.requestData(DriverTestMessage.error().toString());
  //     }

  //     response = Response.fromJson(jsonResponse);
  //   } else if (webDriverCommand == '${WebDriverCommandType.ack}') {
  //     // Previous command completed ask for a new one.
  //     jsonResponse =
  //         await driver.requestData(DriverTestMessage.pending().toString());

  //     response = Response.fromJson(jsonResponse);
  //   } else {
  //     break;
  //   }
  // }

  // // If No-op command is sent, ask for the result of all tests.
  // if (response.data != null &&
  //     response.data!['web_driver_command'] != null &&
  //     response.data!['web_driver_command'] == '${WebDriverCommandType.noop}') {
  //   jsonResponse = await driver.requestData(null);

  //   response = Response.fromJson(jsonResponse);
  //   print('result $jsonResponse');
  // }

  if (response.data != null &&
      response.data!['glaceStackTraces'] != null &&
      onCheckStackTrace != null) {
    final List<dynamic> screenshots =
        response.data!['glaceStackTraces'] as List<dynamic>;
    final List<String> failures = <String>[];
    for (final dynamic screenshot in screenshots) {
      final Map<String, dynamic> data = screenshot as Map<String, dynamic>;
      // final List<dynamic> screenshotBytes = data['bytes'] as List<dynamic>;
      final String screenshotName = data['stackTraceName'] as String;
      final String stackTrace = data['glaceStackTrace'] as String;

      bool ok = false;
      try {
        ok = onScreenshotResults[screenshotName] ??
            await onCheckStackTrace(screenshotName, stackTrace);
      } catch (exception) {
        throw StateError(
          'Check glace stack trace failure:\n'
          'onScreenshot("$screenshotName", <bytes>) threw an exception: $exception',
        );
      }
      if (!ok) {
        failures.add(screenshotName);
      }
    }
    if (failures.isNotEmpty) {
      throw StateError(
          'The following check glace stack trace tests failed: ${failures.join(', ')}');
    }
  }

  await driver.close();

  if (response.allTestsPassed) {
    print('All tests passed.');
    if (responseDataCallback != null) {
      await responseDataCallback(response.data);
    }
    exit(0);
  } else {
    print('Failure Details:\n${response.formattedFailureDetails}');
    if (responseDataCallback != null && writeResponseOnFailure) {
      await responseDataCallback(response.data);
    }
    exit(1);
  }
}

Future<void> main() async {
  await glanceIntegrationDriver(
    onCheckStackTrace: (name, stackTrace) async {
      print('name: $name');
      print('stackTrace: $stackTrace');
      return true;
    },
  );

  // await integrationDriver();
}
