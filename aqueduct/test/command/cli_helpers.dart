import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/runner.dart';
import 'package:aqueduct/src/cli/running_process.dart';

class Terminal {
  Terminal(this.workingDirectory) {
    workingDirectory.createSync(recursive: true);
  }

  Terminal.current() : this(Directory.current);

  final Directory workingDirectory;

  static Directory get temporaryDirectory =>
      Directory.fromUri(Directory.current.uri.resolve("tmp/"));

  static Directory get emptyProjectDirectory => Directory.fromUri(
      Directory.current.uri.resolve("test/").resolve("empty_project/"));

  List<String> defaultAqueductArgs;
  String get output {
    return _output.toString();
  }

  StringBuffer _output = StringBuffer();

  static Future activateCLI({String path = "."}) {
    final cmd = Platform.isWindows ? "pub.bat" : "pub";

    return Process.run(cmd, ["global", "activate", "-spath", path]);
  }

  static Future deactivateCLI() {
    final cmd = Platform.isWindows ? "pub.bat" : "pub";

    return Process.run(cmd, ["global", "deactivate", "aqueduct"]);
  }

  static Future<Terminal> createProject(
      {String name = "application_test",
      String template,
      bool offline = true}) async {
    if (template == null) {
      // Copy empty project
      final projectDir =
          Directory.fromUri(temporaryDirectory.uri.resolve(name));
      final libDir = Directory.fromUri(projectDir.uri.resolve("lib/"));
      libDir.createSync(recursive: true);

      File.fromUri(projectDir.uri.resolve("pubspec.yaml"))
          .writeAsStringSync(_emptyProjectPubspec);
      File.fromUri(libDir.uri.resolve("channel.dart"))
          .writeAsStringSync(_emptyProjectChannel);
      File.fromUri(libDir.uri.resolve("application_test.dart"))
          .writeAsStringSync(_emptyProjectLibrary);

      return Terminal(projectDir);
    }

    try {
      temporaryDirectory.createSync();
    } catch (_) {}

    final creator = Terminal(temporaryDirectory);

    final args = <String>[];
    if (template != null) {
      args.addAll(["-t", template]);
    }

    if (offline) {
      args.add("--offline");
    }

    args.add(name);

    await creator.runAqueductCommand("create", args);
    print("${creator.output}");

    return Terminal(
        Directory.fromUri(temporaryDirectory.uri.resolve("$name/")));
  }

  static void deleteTemporaryDirectory() {
    try {
      temporaryDirectory.deleteSync(recursive: true);
    } catch (_) {}
  }

  Directory get defaultMigrationDirectory {
    return Directory.fromUri(workingDirectory.uri.resolve("migrations/"));
  }

  Directory get libraryDirectory {
    return Directory.fromUri(workingDirectory.uri.resolve("lib/"));
  }

  void clearOutput() {
    _output.clear();
  }

  void addOrReplaceFile(String path, String contents,
      {bool importAqueduct = true}) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    file.writeAsStringSync(
        "${importAqueduct ? "import 'package:aqueduct/aqueduct.dart';\n" : ""}$contents");
  }

  void modifyFile(String path, String contents(String current)) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
        pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
        workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      throw ArgumentError("File at '${file.uri}' doesn't exist.");
    }

    final output = contents(file.readAsStringSync());
    file.writeAsStringSync(output);
  }

  File getFile(String path) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents =
    pathComponents.sublist(0, pathComponents.length - 1);
    final directory = Directory.fromUri(relativeDirectoryComponents.fold(
      workingDirectory.uri, (Uri prev, elem) => prev.resolve("$elem/")));
    final file = File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      return null;
    }
    return file;
  }

  Future<int> executeMigrations(
      {String connectString =
          "postgres://dart:dart@localhost:5432/dart_test"}) async {
    final res =
        await runAqueductCommand("db", ["upgrade", "--connect", connectString]);
    if (res != 0) {
      print("executeMigrations failed: $output");
    }
    return res;
  }

  Future writeMigrations(List<Schema> schemas) async {
    try {
      defaultMigrationDirectory.createSync();
    } catch (_) {}
    var currentNumberOfMigrations = defaultMigrationDirectory
        .listSync()
        .where((e) => e.path.endsWith("migration.dart"))
        .length;

    for (var i = 1; i < schemas.length; i++) {
      var source =
          Migration.sourceForSchemaUpgrade(schemas[i - 1], schemas[i], i);

      var file = File.fromUri(defaultMigrationDirectory.uri
          .resolve("${i + currentNumberOfMigrations}.migration.dart"));
      file.writeAsStringSync(source);
    }
  }

  Future<ProcessResult> getDependencies({bool offline = true}) async {
    var args = ["get", "--no-packages-dir"];
    if (offline) {
      args.add("--offline");
    }

    final cmd = Platform.isWindows ? "pub.bat" : "pub";
    var result = await Process.run(cmd, args,
            workingDirectory: workingDirectory.absolute.path, runInShell: true)
        .timeout(Duration(seconds: 45));

    if (result.exitCode != 0) {
      throw Exception("${result.stderr}");
    }

    return result;
  }

  Future<int> runAqueductCommand(String command, [List<String> args]) async {
    args ??= [];
    args.insert(0, command);
    args.addAll(defaultAqueductArgs ?? []);

    print("Running 'aqueduct ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = workingDirectory;

    var cmd = Runner()..outputSink = _output;
    var results = cmd.options.parse(args);

    final exitCode = await cmd.process(results);
    if (exitCode != 0) {
      print("command failed: ${output}");
    }

    Directory.current = saved;

    return exitCode;
  }

  CLITask startAqueductCommand(String command, List<String> inputArgs) {
    final args = inputArgs ?? [];
    args.insert(0, command);
    args.addAll(defaultAqueductArgs ?? []);

    print("Starting 'aqueduct ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = workingDirectory;

    var cmd = Runner()..outputSink = _output;
    var results = cmd.options.parse(args);

    final task = CLITask();
    var elapsed = 0.0;
    final timer = Timer.periodic(Duration(milliseconds: 100), (t) {
      if (cmd.runningProcess != null) {
        t.cancel();
        Directory.current = saved;
        task.process = cmd.runningProcess;
        task._processStarted.complete(true);
      } else {
        elapsed += 100;
        if (elapsed > 60000) {
          Directory.current = saved;
          t.cancel();
          task._processStarted
              .completeError(TimeoutException("Timed out after 30 seconds"));
        }
      }
    });

    cmd.process(results).then((exitCode) {
      if (!task._processStarted.isCompleted) {
        print("Command failed to start with exit code: $exitCode");
        print("Message: $output");
        timer.cancel();
        Directory.current = saved;
        task._processStarted.completeError(false);
        task._processFinished.complete(exitCode);
      } else {
        print("Command completed with exit code: $exitCode");
        print("Output: $output");
        task._processFinished.complete(exitCode);
      }
    });

    return task;
  }

  static const _emptyProjectPubspec = """
name: application_test
description: A web server application.
version: 0.0.1

environment:
  sdk: ">=2.0.0 <3.0.0"

dependencies:
  aqueduct:
    path: ../..

dev_dependencies:
  test: ^1.0.0  
  """;

  static const _emptyProjectLibrary = """
export 'package:aqueduct/aqueduct.dart';
export 'channel.dart';  
  """;

  static const _emptyProjectChannel = """
import 'dart:async';
import 'application_test.dart';
import 'package:aqueduct/aqueduct.dart';
class TestChannel extends ApplicationChannel {
  Controller get entryPoint {
    final router = new Router();
    router
      .route("/example")
      .linkFunction((request) async {
        return new Response.ok({"key": "value"});
      });

    return router;
  }
}  
  """;
}

class CLIResult {
  int exitCode;
  StringBuffer collectedOutput = StringBuffer();

  String get output => collectedOutput.toString();
}

class CLITask {
  StoppableProcess process;

  Future get hasStarted => _processStarted.future;
  Future<int> get exitCode => _processFinished.future;

  Completer<int> _processFinished = Completer<int>();
  Completer<bool> _processStarted = Completer<bool>();
}
