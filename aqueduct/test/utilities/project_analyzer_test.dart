import 'dart:io';

import 'package:test/test.dart';
import 'package:aqueduct/src/compilers/project_analyzer.dart';

import '../command/cli_helpers.dart';

void main() {
  Terminal terminal;

  tearDown(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("ProjectAnalyzer can find a specific class declaration in project",
      () async {
    terminal = await Terminal.createProject();
    await terminal.getDependencies();

    terminal =
        Terminal(Directory.fromUri(Uri.file("tmp/application_test/")));

    var path = terminal.workingDirectory.absolute.uri;
    final p = CodeAnalyzer(path);
    final klass = p.getClassFromFile("TestChannel",
        terminal.libraryDirectory.absolute.uri.resolve("channel.dart").path);
    expect(klass, isNotNull);
    expect(klass.name.name, "TestChannel");
    expect(klass.extendsClause.superclass.name.name, "ApplicationChannel");
  });

  test("Can create CodeAnalyzer for a single file", () async {
    terminal = await Terminal.createProject();

    // we can inherit dependencies from parent directory
    var path = terminal.workingDirectory.absolute.uri.resolve("pubspec.yaml");
    final p = CodeAnalyzer(path);

    final expectedPath = terminal.workingDirectory.absolute.uri.resolve("pubspec.yaml");
    expect(
        p.contexts
            .contextFor(expectedPath.path)
            .contextRoot
            .isAnalyzed(expectedPath.path),
        true);
  });
}
