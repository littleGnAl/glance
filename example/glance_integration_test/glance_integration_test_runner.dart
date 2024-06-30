import 'package:process/process.dart';
import 'package:file/file.dart' as file;
import 'package:file/local.dart';

import '_test_runner.dart';

void main() {
  const processManager = LocalProcessManager();
  const file.FileSystem fileSystem = LocalFileSystem();
  runTest(processManager, fileSystem);
}
