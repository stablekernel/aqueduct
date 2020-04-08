// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:convert';

import 'package:command_line_agent/command_line_agent.dart';
import 'package:test/test.dart';

import '../not_tests/cli_helpers.dart';

void main() {
  CLIClient terminal;

  setUpAll(() async {
    await CLIClient.activateCLI();
    final t = CLIClient(CommandLineAgent(ProjectAgent.projectsDirectory));
    terminal = await t.createProject(template: "db_and_auth");
  });

  tearDownAll(() async {
    await CLIClient.deactivateCLI();
    ProjectAgent.tearDownAll();
  });

  tearDown(() {
    terminal.clearOutput();
  });

  test("Document command uses project pubspec for metadata", () async {
    await terminal.run("document", ["--machine"]);

    final map = json.decode(terminal.output);
    expect(map["info"]["title"], "application_test");
    expect(map["info"]["version"], "0.0.1");
    expect(map["info"]["description"], isNotNull);
  });

  test("Can override title/version/etc.", () async {
    await terminal.run("document",
        ["--machine", "--title", "foobar", "--api-version", "2.0.0"]);

    final map = json.decode(terminal.output);
    expect(map["info"]["title"], "foobar");
    expect(map["info"]["version"], "2.0.0");
  });

  test("Can set license, contact", () async {
    await terminal.run("document", [
      "--machine",
      "--license-url",
      "http://whatever.com",
      "--license-name",
      "bsd",
      "--contact-email",
      "a@b.com"
    ]);

    final map = json.decode(terminal.output);
    expect(map["info"]["license"]["name"], "bsd");
    expect(map["info"]["license"]["url"], "http://whatever.com");
    expect(map["info"]["contact"]["email"], "a@b.com");
  });

  test("Can view error stacktrace when failing to doc", () async {
    terminal.agent.modifyFile("lib/controller/identity_controller.dart", (contents) {
      final lastCurly = contents.lastIndexOf("}");
      return contents.replaceRange(lastCurly, lastCurly, """
        @override 
        void documentComponents(APIDocumentContext ctx) {
          throw new Exception("Hello!");
        }
      """);
    });

    final exitCode = await terminal
        .run("document", ["--machine", "--stacktrace"]);
    expect(exitCode, isNot(0));
    expect(terminal.output, contains("IdentityController.documentComponents"));
    expect(terminal.output, contains("Exception: Hello!"));
  });
}
