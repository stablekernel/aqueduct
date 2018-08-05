// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  Terminal terminal = Terminal(Terminal.temporaryDirectory);

  setUpAll(() async {
    await Terminal.activateCLI();
    terminal = await Terminal.createProject();
    await terminal.getDependencies();
  });

  tearDownAll(() async {
    await Terminal.deactivateCLI();
    Terminal.deleteTemporaryDirectory();
  });

  tearDown(() async {
    terminal.getFile("client.html").deleteSync();
  });

  test("command with default args creates client page from current project dir pointing at localhost:8888", () async {
    await terminal.runAqueductCommand("document", ["client"]);

    final clientContents = terminal.getFile("client.html")?.readAsStringSync();
    expect(clientContents, contains('spec: {"openapi":"3.0.0"'));
    expect(clientContents, contains('<script src="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui-bundle.js"></script>'));
  });
}
