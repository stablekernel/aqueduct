// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'cli_helpers.dart';

void main() {
  Terminal template;
  Terminal terminal;

  setUpAll(() async {
    await Terminal.activateCLI();
    template = await Terminal.createProject(template: "db_and_auth");
    await terminal.getDependencies();
  });

  tearDownAll(() async {
    await Terminal.deactivateCLI();
  });

  setUp(() async {
    terminal = template.replicate();
  });

  tearDown(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("Can get API reference", () async {
    final task = terminal.startAqueductCommand("document", ["serve"]);
    await task.hasStarted;

    expect(
        Directory.fromUri(
                terminal.workingDirectory.uri.resolve(".aqueduct_spec/"))
            .existsSync(),
        true);

    var response = await http.get("http://localhost:8111");
    expect(response.body, contains("redoc spec-url='openapi.json'"));

    // ignore: unawaited_futures
    task.process.stop(0);
    expect(await task.exitCode, 0);
    expect(
        Directory.fromUri(
                terminal.workingDirectory.uri.resolve(".aqueduct_spec/"))
            .existsSync(),
        false);
  });
}
