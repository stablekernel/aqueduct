import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'cli_helpers.dart';

void main() {
  Terminal terminal = new Terminal(Terminal.temporaryDirectory);

  setUpAll(() async {
    await Process.run("pub", ["global", "activate", "-spath", "."]);
    terminal = await Terminal.createProject(template: "db_and_auth");
    await terminal.getDependencies();
  });

  tearDown(() async {
    await Process.run("pub", ["global", "deactivate", "aqueduct"]);
    Terminal.deleteTemporaryDirectory();
  });

  test("Can get API reference", () async {
    final task = terminal.startAqueductCommand("document", ["serve"]);
    await task.hasStarted;

    expect(new Directory.fromUri(terminal.workingDirectory.uri.resolve(".aqueduct_spec/")).existsSync(), true);

    var response = await http.get("http://localhost:8111");
    expect(response.body, contains("redoc spec-url='swagger.json'"));

    task.process.stop(0);
    expect(await task.exitCode, 0);
    expect(new Directory.fromUri(terminal.workingDirectory.uri.resolve(".aqueduct_spec/")).existsSync(), false);
  });
}