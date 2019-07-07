import 'dart:async';

Future main(List<String> args) async {
  /*
  final testDir = Directory.fromUri(Directory.current.uri.resolve("test/"));
  final testFiles = testDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith("_test.dart"))
      .toList();

  // exclude test files that have a 'vm-only' tag
  // generate/link runtimes for each test file (* need to remove all .. from imported paths)
  // run each generated/linked test file with 'dart' cmd
  // track exit code (?) of each test file; if any is an error, emit that as exit code of this script
  // ensure console output from each test file is logged to this script's output stream
  */
}
