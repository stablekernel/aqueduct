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

    var path = terminal.workingDirectory.uri;
    final p = ProjectAnalyzer(path);
    expect(path.path, equals("${p.context.contextRoot.root.path}/"));

    final klass = p.getClassFromFile("TestChannel", relativePath: "lib/channel.dart");
    expect(klass, isNotNull);
    expect(klass.name.name, "TestChannel");
    expect(klass.extendsClause.superclass.name.name, "ApplicationChannel");
  });

  test("Can create CodeAnalyzer for a single file", () async {
    terminal = await Terminal.createProject();

    // we can inherit dependencies from parent directory
    var path = terminal.workingDirectory.uri.resolve("pubspec.yaml");
    final p = CodeAnalyzer(path);

    expect(p.context.contextRoot.analyzedFiles().length, 1);
    final expectedPath = terminal.workingDirectory.uri.resolve("pubspec.yaml");
    expect(Uri.file(p.context.contextRoot.analyzedFiles().first), expectedPath);
  });

  test(
      "If ProjectAnalyzer does not have package config, throws exception to indicate run pub get",
      () async {
    terminal = await Terminal.createProject();
    var path = terminal.workingDirectory.uri;

    try {
      ProjectAnalyzer(path);
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Run 'pub get'"));
    }
  });
}
