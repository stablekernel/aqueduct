import 'dart:io';
import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/executable.dart';
import 'package:http/http.dart' as http;

import '../helpers.dart';

void main() {
  var temporaryDirectory = new Directory("test_project");
  var testDirectory =
      new Directory.fromUri(Directory.current.uri.resolve("test"));
  var commandDirectory =
      new Directory.fromUri(testDirectory.uri.resolve("command"));
  var sourceDirectory =
      new Directory.fromUri(commandDirectory.uri.resolve("serve_test_project"));

  tearDown(() async {
    await runAqueductProcess(["serve", "stop"], temporaryDirectory);
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    createTestProject(sourceDirectory, temporaryDirectory);
    await runPubGet(temporaryDirectory, offline: true);
  });

  test("Served application starts and responds to route", () async {
    var res =
        await runAqueductProcess(["serve", "--detached"], temporaryDirectory);
    expect(res, 0);

    var result = await http.get("http://localhost:8081/endpoint");
    expect(result.statusCode, 200);
  });

  test("Ensure we don't find the base RequestSink class", () async {
    var libDir = new Directory.fromUri(temporaryDirectory.uri.resolve("lib"));
    var libFile = new File.fromUri(libDir.uri.resolve("wildfire.dart"));
    libFile.writeAsStringSync("import 'package:aqueduct/aqueduct.dart';");

    var res = await runAqueductProcess(["serve"], temporaryDirectory);
    expect(res != 0, true);
  });

  test("Exception throw during initializeApplication halts startup", () async {
    var libDir = new Directory.fromUri(temporaryDirectory.uri.resolve("lib"));
    var libFile = new File.fromUri(libDir.uri.resolve("wildfire.dart"));
    addLinesToFile(
        libFile,
        "class WildfireSink extends RequestSink {",
        """
    static Future initializeApplication(ApplicationConfiguration x) async { throw new Exception("error"); }
    """);

    var res = await runAqueductProcess(["serve"], temporaryDirectory);
    expect(res != 0, true);
  });

  test("Start with valid SSL args opens https server", () async {
    var certFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.cert.pem"));
    var keyFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.key.pem"));

    certFile.copySync(temporaryDirectory.uri.resolve("server.crt").path);
    keyFile.copySync(temporaryDirectory.uri.resolve("server.key").path);

    var res = await runAqueductProcess(
          ["serve", "--detached", "--ssl-key-path", "server.key", "--ssl-certificate-path", "server.crt"],
          temporaryDirectory);
    expect(res, 0);

    var completer = new Completer();
    var socket = await SecureSocket.connect("localhost", 8081, onBadCertificate: (_) => true);
    var request = "GET /endpoint HTTP/1.1\r\nConnection: close\r\nHost: localhost\r\n\r\n";
    socket.add(request.codeUnits);

    socket.listen((bytes) => completer.complete(bytes));
    var httpResult = new String.fromCharCodes(await completer.future);
    expect(httpResult, contains("200 OK"));
    await socket.close();
  });

  test("Start without one of SSL values throws exception", () async {
    var certFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.cert.pem"));
    var keyFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.key.pem"));

    certFile.copySync(temporaryDirectory.uri.resolve("server.crt").path);
    keyFile.copySync(temporaryDirectory.uri.resolve("server.key").path);

    var res = await runAqueductProcess(
        ["serve", "--detached", "--ssl-key-path", "server.key"],
        temporaryDirectory);
    expect(res, 1);

    res = await runAqueductProcess(
        ["serve", "--detached", "--ssl-certificate-path", "server.crt"],
        temporaryDirectory);
    expect(res, 1);
  });

  test("Start with invalid SSL values throws exceptions", () async {
    var keyFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.key.pem"));
    keyFile.copySync(temporaryDirectory.uri.resolve("server.key").path);

    var badCertFile = new File.fromUri(temporaryDirectory.uri.resolve("server.crt"));
    badCertFile.writeAsStringSync("foobar");

    var res = await runAqueductProcess(
        ["serve", "--detached", "--ssl-key-path", "server.key", "--ssl-certificate-path", "server.crt"],
        temporaryDirectory);
    expect(res, 1);
  });

  test("Can't find SSL file, throws exception", () async {
    var keyFile = new File.fromUri(new Directory("ci").uri.resolve("aqueduct.key.pem"));
    keyFile.copySync(temporaryDirectory.uri.resolve("server.key").path);

    var res = await runAqueductProcess(
        ["serve", "--detached", "--ssl-key-path", "server.key", "--ssl-certificate-path", "server.crt"],
        temporaryDirectory);
    expect(res, 1);
  });
}

Future<int> runAqueductProcess(
    List<String> commands, Directory workingDirectory) async {
  commands.add("--directory");
  commands.add("${workingDirectory.path}");

  var cmd = new Runner();
  var results = cmd.options.parse(commands);

  return cmd.process(results);
}

void addLinesToFile(
    File file, String afterFindingThisString, String insertThisString) {
  var contents = file.readAsStringSync();
  var indexOf =
      contents.indexOf(afterFindingThisString) + afterFindingThisString.length;
  var newContents = contents.replaceRange(indexOf, indexOf, insertThisString);
  file.writeAsStringSync(newContents);
}
