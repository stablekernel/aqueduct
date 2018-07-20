// ignore: unnecessary_const
@Tags(const ["cli"])
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart' as yaml;
import 'package:pub_semver/pub_semver.dart';

import 'cli_helpers.dart';

File get certificateFile => File.fromUri(Directory.current.uri
    .resolve("../")
    .resolve("ci/")
    .resolve("aqueduct.cert.pem"));

File get keyFile => File.fromUri(Directory.current.uri
    .resolve("../")
    .resolve("ci/")
    .resolve("aqueduct.key.pem"));

void main() {
  Terminal terminal;
  CLITask task;

  setUp(() async {
    terminal = await Terminal.createProject();
    await terminal.getDependencies(offline: true);
  });

  tearDown(() async {
    await task?.process?.stop(0);
    Terminal.deleteTemporaryDirectory();
  });

  test("Served application starts and responds to route", () async {
    task = terminal.startAqueductCommand("serve", ["-n", "1"]);
    await task.hasStarted;

    expect(terminal.output, contains("Port: 8888"));
    expect(terminal.output, contains("config.yaml"));

    var thisPubspec = yaml.loadYaml(
        File.fromUri(Directory.current.uri.resolve("pubspec.yaml"))
            .readAsStringSync());
    var thisVersion = Version.parse(thisPubspec["version"] as String);
    expect(terminal.output, contains("CLI Version: $thisVersion"));
    expect(terminal.output, contains("Aqueduct project version: $thisVersion"));

    var result = await http.get("http://localhost:8888/example");
    expect(result.statusCode, 200);

    // ignore: unawaited_futures
    task.process.stop(0);
    expect(await task.exitCode, 0);
  });

  test("Ensure we don't find the base ApplicationChannel class", () async {
    terminal.addOrReplaceFile("lib/application_test.dart",
        "import 'package:aqueduct/aqueduct.dart';");

    task = terminal.startAqueductCommand("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
    expect(terminal.output, contains("No ApplicationChannel subclass"));
  });

  test("Exception throw during initializeApplication halts startup", () async {
    terminal.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst(
          "extends ApplicationChannel {", """extends ApplicationChannel {
static Future initializeApplication(ApplicationOptions x) async { throw new Exception("error"); }            
      """);
    });

    task = terminal.startAqueductCommand("serve", ["-n", "1"]);

    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
    expect(terminal.output, contains("Application failed to start"));
    expect(terminal.output, contains("Exception: error")); // error generated
    expect(terminal.output,
        contains("TestChannel.initializeApplication")); // stacktrace
  });

  test("Start with valid SSL args opens https server", () async {
    certificateFile.copySync(terminal.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(terminal.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = terminal.startAqueductCommand("serve", [
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
    certificateFile.copySync(terminal.workingDirectory.uri
        .resolve("server.crt")
        .toFilePath(windows: Platform.isWindows));
    keyFile.copySync(terminal.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = terminal.startAqueductCommand(
        "serve", ["--ssl-key-path", "server.key", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));

    task = terminal.startAqueductCommand(
        "serve", ["--ssl-certificate-path", "server.crt", "-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);
    expect(await task.exitCode, isNot(0));
  });

  test("Start with invalid SSL values throws exceptions", () async {
    keyFile.copySync(terminal.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    var badCertFile =
        File.fromUri(terminal.workingDirectory.uri.resolve("server.crt"));
    badCertFile.writeAsStringSync("foobar");

    task = terminal.startAqueductCommand("serve", [
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
    keyFile.copySync(terminal.workingDirectory.uri
        .resolve("server.key")
        .toFilePath(windows: Platform.isWindows));

    task = terminal.startAqueductCommand("serve", [
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
    terminal.modifyFile("lib/channel.dart", (contents) {
      return contents.replaceFirst("import", "importasjakads");
    });

    task = terminal.startAqueductCommand("serve", ["-n", "1"]);
    // ignore: unawaited_futures
    task.hasStarted.catchError((_) => null);

    expect(await task.exitCode, isNot(0));
    expect(terminal.output,
        contains("Variables must be declared using the keywords"));
  });

  test("Use config-path, relative path", () async {
    terminal.addOrReplaceFile("foobar.yaml", "key: value",
        importAqueduct: false);
    terminal.modifyFile("lib/channel.dart", (c) {
      var newContents = c.replaceAll(
          'return new Response.ok({"key": "value"});',
          "return new Response.ok(new File(options.configurationFilePath).readAsStringSync())..contentType = ContentType.TEXT;");
      return "import 'dart:io';\n$newContents";
    });

    task = terminal.startAqueductCommand(
        "serve", ["--config-path", "foobar.yaml", "-n", "1"]);
    await task.hasStarted;

    var result = await http.get("http://localhost:8888/example");
    expect(result.body, "key: value");
  });

  test("Use config-path, absolute path", () async {
    terminal.addOrReplaceFile("foobar.yaml", "key: value",
        importAqueduct: false);
    terminal.modifyFile("lib/channel.dart", (c) {
      var newContents = c.replaceAll(
          'return new Response.ok({"key": "value"});',
          "return new Response.ok(new File(options.configurationFilePath).readAsStringSync())..contentType = ContentType.TEXT;");
      return "import 'dart:io';\n$newContents";
    });

    task = terminal.startAqueductCommand("serve", [
      "--config-path",
      terminal.workingDirectory.uri
          .resolve("foobar.yaml")
          .toFilePath(windows: Platform.isWindows),
      "-n",
      "1"
    ]);
    await task.hasStarted;

    var result = await http.get("http://localhost:8888/example");
    expect(result.body, "key: value");
  });
}
