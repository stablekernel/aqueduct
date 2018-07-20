// ignore: unnecessary_const
@Tags(const ["cli"])

import 'package:test/test.dart';
import 'cli_helpers.dart';

void main() {
  Terminal terminal;

  // This group handles checking the tool itself,
  // not the behavior of creating the appropriate migration file given schemas
  setUp(() async {
    terminal = await Terminal.createProject();
    terminal.addOrReplaceFile("lib/application_test.dart", """
import 'package:aqueduct/aqueduct.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @primaryKey
  int id;

  String foo;
}
      """);
  });

  tearDown(Terminal.deleteTemporaryDirectory);

  test("Ensure migration directory will get created on generation", () async {
    await terminal.getDependencies(offline: true);
    var res = await terminal.runAqueductCommand("db", ["schema"]);
    expect(res, 0);
    expect(terminal.output, contains("_TestObject"));
  });
}
