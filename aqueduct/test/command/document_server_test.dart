@Tags(const ["cli"])
@Skip("Waiting on https://github.com/dart-lang/sdk/issues/33207")
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'cli_helpers.dart';

void main() {
  Terminal terminal = new Terminal(Terminal.temporaryDirectory);

  setUpAll(() async {
    await Terminal.activateCLI();
  });

  tearDownAll(() async {
    await Terminal.deactivateCLI();

  });

  setUp(() async {
    terminal = await Terminal.createProject(template: "db_and_auth");
    await terminal.getDependencies();
  });

  tearDown(() async {
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