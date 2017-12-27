import 'dart:io';
import 'dart:convert';

import 'package:test/test.dart';

void main() {
  test("Document command uses project pubspec for metadata", () async {
    final result = await Process.run("pub", ["global", "run", "aqueduct:aqueduct", "document"],
        runInShell: true,
        workingDirectory:
            Directory.current.uri.resolve("test/").resolve("command/").resolve("serve_test_project/").path);

    final map = JSON.decode(result.stdout);
    expect(map["info"]["title"], "wildfire");
    expect(map["info"]["version"], "0.0.1");
    expect(map["info"]["description"], "A web server application.");
  });
}