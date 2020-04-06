// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:command_line_agent/command_line_agent.dart';
import 'package:test/test.dart';

import '../not_tests/cli_helpers.dart';

void main() {
  CLIClient cli;

  // This group handles checking the tool itself,
  // not the behavior of creating the appropriate migration file given schemas
  setUp(() async {
    cli = await CLIClient(CommandLineAgent(ProjectAgent.projectsDirectory)).createProject();
    await cli.agent.getDependencies(offline: true);
    cli.agent.addOrReplaceFile("lib/application_test.dart", """
import 'package:aqueduct/aqueduct.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
  });

  tearDown(ProjectAgent.tearDownAll);

  test("Ensure migration directory will get created on generation", () async {
    var res = await cli.run("db", ["schema"]);
    expect(res, 0);
    expect(cli.output, contains("_TestObject"));
  });
}
