// ignore: unnecessary_const
@Tags(const ["cli"])
import 'package:test/test.dart';

import 'cli_helpers.dart';

void main() {
  Terminal terminal = Terminal(Terminal.temporaryDirectory);

  setUpAll(() async {
    await Terminal.activateCLI();
  });

  tearDownAll(() async {
    await Terminal.deactivateCLI();
  });

  tearDown(() async {
    Terminal.deleteTemporaryDirectory();
  });

  test("command with default args creates client page from current project dir pointing at localhost:8888", () async {
    terminal = await Terminal.createProject(template: "db_and_auth");
    await terminal.getDependencies();

    await terminal.runAqueductCommand("document", ["client"]);

    final clientContents = terminal.getFile("client.html")?.readAsStringSync();
    expect(clientContents, contains('spec: {"openapi":"3.0.0"'));
    expect(clientContents, contains('<script src="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui-bundle.js"></script>'));

    // make sure auth urls were replaced
    expect(clientContents, contains('"authorizationUrl":"http://localhost:8888/auth/form"'));
    expect(clientContents, contains('"tokenUrl":"http://localhost:8888/auth/token"'));
    expect(clientContents, contains('"refreshUrl":"http://localhost:8888/auth/token"'));
  });

  test("Replace relative urls with provided server", () async {
    terminal = await Terminal.createProject(template: "db_and_auth");
    await terminal.getDependencies();

    await terminal.runAqueductCommand("document", ["client", "--host", "https://server.com/v1/"]);

    final clientContents = terminal.getFile("client.html")?.readAsStringSync();
    expect(clientContents, contains('spec: {"openapi":"3.0.0"'));
    expect(clientContents, contains('<script src="https://unpkg.com/swagger-ui-dist@3.12.1/swagger-ui-bundle.js"></script>'));

    // make sure auth urls were replaced
    expect(clientContents, contains('"authorizationUrl":"https://server.com/v1/auth/form"'));
  });
}
