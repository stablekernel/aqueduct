// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:convert';

import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  Terminal terminal;

  setUpAll(() async {
    await Terminal.activateCLI();
  });

  tearDownAll(() async {
    await Terminal.deactivateCLI();
  });

  setUp(() async {
    terminal = await Terminal.createProject(template: "db_and_auth");
  });

  tearDown(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("Document command uses project pubspec for metadata", () async {
    await terminal.runAqueductCommand("document", ["--machine"]);

    final map = json.decode(terminal.output);
    expect(map["info"]["title"], "application_test");
    expect(map["info"]["version"], "0.0.1");
    expect(map["info"]["description"], isNotNull);
  });

  test("Can override title/version/etc.", () async {
    await terminal.runAqueductCommand("document",
        ["--machine", "--title", "foobar", "--api-version", "2.0.0"]);

    final map = json.decode(terminal.output);
    expect(map["info"]["title"], "foobar");
    expect(map["info"]["version"], "2.0.0");
  });

  test("Can set license, contact", () async {
    await terminal.runAqueductCommand("document", [
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
    terminal.modifyFile("lib/controller/identity_controller.dart", (contents) {
      final lastCurly = contents.lastIndexOf("}");
      return contents.replaceRange(lastCurly, lastCurly, """
        @override 
        void documentComponents(APIDocumentContext ctx) {
          throw new Exception("Hello!");
        }
      """);
    });

    final exitCode = await terminal
        .runAqueductCommand("document", ["--machine", "--stacktrace"]);
    expect(exitCode, isNot(0));
    expect(terminal.output, contains("IdentityController.documentComponents"));
    expect(terminal.output, contains("Exception: Hello!"));
  });
}
