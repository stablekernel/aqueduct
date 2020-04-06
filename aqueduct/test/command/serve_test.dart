// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:async';
import 'dart:io';

import 'package:command_line_agent/command_line_agent.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart' as yaml;
import 'package:pub_semver/pub_semver.dart';

import '../not_tests/cli_helpers.dart';

File get certificateFile => File.fromUri(Directory.current.uri
    .resolve("../")
    .resolve("ci/")
    .resolve("aqueduct.cert.pem"));

File get keyFile => File.fromUri(Directory.current.uri
    .resolve("../")
    .resolve("ci/")
    .resolve("aqueduct.key.pem"));

void main() {
  CLIClient templateCli;
  CLIClient projectUnderTestCli;
  CLITask task;

  setUpAll(() async {
    templateCli = await CLIClient(CommandLineAgent(ProjectAgent.projectsDirectory)).createProject();
    await templateCli.agent.getDependencies(offline: true);
  });

  setUp(() async {
    projectUnderTestCli = templateCli.replicate(Uri.parse("replica/"));
  });

  tearDown(() async {
    await task?.process?.stop(0);
  });

  tearDownAll(ProjectAgent.tearDownAll);

  test("Served application starts and responds to route", () async {
    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    await task.hasStarted;

    expect(projectUnderTestCli.output, contains("Port: 8888"));
    expect(projectUnderTestCli.output, contains("config.yaml"));

    var thisPubspec = yaml.loadYaml(
        File.fromUri(Directory.current.uri.resolve("pubspec.yaml"))
            .readAsStringSync());
    var thisVersion = Version.parse(thisPubspec["version"] as String);
    expect(projectUnderTestCli.output, contains("CLI Version: $thisVersion"));
    expect(projectUnderTestCli.output, contains("Aqueduct project version: $thisVersion"));

    var result = await http.get("http://localhost:8888/example");
    expect(result.statusCode, 200);

    // ignore: unawaited_futures
    task.process.stop(0);
    expect(await task.exitCode, 0);
  });

  test("Ensure we don't find the base ApplicationChannel class", () async {
    projectUnderTestCli.agent.addOrReplaceFile("lib/application_test.dart",
        "import 'package:aqueduct/aqueduct.dart';");

    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
    expect(projectUnderTestCli.output, contains("No ApplicationChannel subclass"));
  });

  test("Exception throw during initializeApplication halts startup", () async {
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst(
          "extends ApplicationChannel {", """extends ApplicationChannel {
static Future initializeApplication(ApplicationOptions x) async { throw new Exception("error"); }            
      """);
    });

    task = projectUnderTestCli.start("serve", ["-n", "1"]);

    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
    expect(projectUnderTestCli.output, contains("Application failed to start"));
    expect(projectUnderTestCli.output, contains("Exception: error")); // error generated
    expect(projectUnderTestCli.output,
        contains("TestChannel.initializeApplication")); // stacktrace
  });

  test("Start with valid SSL args opens https server", () async {
    certificateFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    await task.hasStarted;

    var completer = Completer<List<int>>();
    var socket = await SecureSocket.connect("localhost", 8888,
        onBadCertificate: (_) => true);
    var request =
        "GET /example HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
    socket.add(request.codeUnits);

    socket.listen((bytes) => completer.complete(bytes));
    var httpResult = String.fromCharCodes(await completer.future);
    expect(httpResult, contains("200 OK"));
    await socket.close();
  });

  test("Start without one of SSL values throws exception", () async {
    certificateFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli.start(
        "serve", ["--ssl-key-path", "server.key", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));

    task = projectUnderTestCli.start(
        "serve", ["--ssl-certificate-path", "server.crt", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
  });

  test("Start with invalid SSL values throws exceptions", () async {
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    var badCertFile =
        File.fromUri(projectUnderTestCli.agent.workingDirectory.uri.resolve("server.crt"));
    badCertFile.writeAsStringSync("foobar");

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
  });

  test("Can't find SSL file, throws exception", () async {
    keyFile.copySync(projectUnderTestCli.agent.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = projectUnderTestCli.start("serve", [
      "--ssl-key-path",
      "server.key",
      "--ssl-certificate-path",
      "server.crt",
      "-n",
      "1"
    ]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
  });

  test("Run application with invalid code fails with error", () async {
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst("import", "importasjakads");
    });

    task = projectUnderTestCli.start("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);

    expect(await task.exitCode, isNot(0));
    expect(projectUnderTestCli.output,
        contains("Variables must be declared using the keywords"));
  });

  test("Use config-path, relative path", () async {
    projectUnderTestCli.agent.addOrReplaceFile("foobar.yaml", "key: value");
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (c) {
      var newContents = c.replaceAll(
          'return new Response.ok({"key": "value"});',
          "return new Response.ok(new File(options.configurationFilePath).readAsStringSync())..contentType = ContentType.TEXT;");
      return "import 'dart:io';\n$newContents";
    });

    task = projectUnderTestCli.start(
        "serve", ["--config-path", "foobar.yaml", "-n", "1"]);
    await task.hasStarted;

    var result = await http.get("http://localhost:8888/example");
    expect(result.body, contains("key: value"));
  });

  test("Use config-path, absolute path", () async {
    projectUnderTestCli.agent.addOrReplaceFile("foobar.yaml", "key: value");
    projectUnderTestCli.agent.modifyFile("lib/channel.dart", (c) {
      var newContents = c.replaceAll(
          'return new Response.ok({"key": "value"});',
          "return new Response.ok(new File(options.configurationFilePath).readAsStringSync())..contentType = ContentType.TEXT;");
      return "import 'dart:io';\n$newContents";
    });

    task = projectUnderTestCli.start("serve", [
      "--config-path",
      projectUnderTestCli.agent.workingDirectory.uri
          .resolve("foobar.yaml")
          .toFilePath(windows: Platform.isWindows),
      "-n",
      "1"
    ]);
    await task.hasStarted;

    var result = await http.get("http://localhost:8888/example");
    expect(result.body, contains("key: value"));
  });
}
