// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:io';

import 'package:command_line_agent/command_line_agent.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import '../not_tests/cli_helpers.dart';

void main() {
  CLIClient templateCli;
  CLIClient projectUnderTestCli;

  setUpAll(() async {
    await CLIClient.activateCLI();
    templateCli = await CLIClient(CommandLineAgent(ProjectAgent.projectsDirectory)).createProject();
    await templateCli.agent.getDependencies(offline: true);
  });

  tearDownAll(() async {
    await CLIClient.deactivateCLI();
    ProjectAgent.tearDownAll();
  });

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
  });

  tearDown(() {
    projectUnderTestCli.agent.workingDirectory.deleteSync(recursive: true);
  });

  test("Can get API reference", () async {
    final task = projectUnderTestCli.start("document", ["serve"]);
    await task.hasStarted;

    expect(
        Directory.fromUri(
                projectUnderTestCli.agent.workingDirectory.uri.resolve(".aqueduct_spec/"))
            .existsSync(),
        true);

    var response = await http.get("http://localhost:8111");
    expect(response.body, contains("redoc spec-url='openapi.json'"));

    // ignore: unawaited_futures
    task.process.stop(0);
    expect(await task.exitCode, 0);
    expect(
        Directory.fromUri(
          projectUnderTestCli.agent.workingDirectory.uri.resolve(".aqueduct_spec/"))
            .existsSync(),
        false);
  });
}
