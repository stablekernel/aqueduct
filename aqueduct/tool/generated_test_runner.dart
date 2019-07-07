import 'dart:async';

import 'dart:io';

Future main(List<String> args) async {
  final testDir = Directory.fromUri(Directory.current.uri.resolve("test/"));
  final testFiles = testDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith("_test.dart"))
      .toList();

  
}
