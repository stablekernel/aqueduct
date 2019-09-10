// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:terminal/terminal.dart';
import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  CLIClient cli;

  // This group handles checking the tool itself,
  // not the behavior of creating the appropriate migration file given schemas
  setUp(() async {
    cli = await CLIClient(Terminal(ProjectTerminal.projectsDirectory)).createProject();
    await cli.terminal.getDependencies(offline: true);
    cli.terminal.addOrReplaceFile("lib/application_test.dart", """
import 'package:aqueduct/aqueduct.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
  });

  tearDown(ProjectTerminal.tearDownAll);

  test("Ensure migration directory will get created on generation", () async {
    var res = await cli.run("db", ["schema"]);
    expect(res, 0);
    expect(cli.output, contains("_TestObject"));
  });
}
