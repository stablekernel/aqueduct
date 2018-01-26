import 'dart:async';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/executable.dart';
import 'dart:io';

import 'package:aqueduct/src/commands/running_process.dart';

class Terminal {
  Terminal(this.workingDirectory) {
    workingDirectory.createSync(recursive: true);
  }

  Terminal.current() : this(Directory.current);

  final Directory workingDirectory;

  static Directory get temporaryDirectory => new Directory.fromUri(Directory.current.uri.resolve("tmp"));

  static Directory get emptyProjectDirectory =>
      new Directory.fromUri(Directory.current.uri.resolve("test/").resolve("empty_project/"));

  List<String> defaultAqueductArgs;
  String get output {
    return _output.toString();
  }
  StringBuffer _output = new StringBuffer();

  static Future<Terminal> createProject({String name: "application_test", String template, bool offline: true}) async {
    if (template == null) {
      // Copy empty project
      final projectDir = new Directory.fromUri(temporaryDirectory.uri.resolve(name));
      final libDir = new Directory.fromUri(projectDir.uri.resolve("lib/"));
      libDir.createSync(recursive: true);

      new File.fromUri(projectDir.uri.resolve("pubspec.yaml")).writeAsStringSync(_emptyProjectPubspec);
      new File.fromUri(libDir.uri.resolve("channel.dart")).writeAsStringSync(_emptyProjectChannel);
      new File.fromUri(libDir.uri.resolve("application_test.dart")).writeAsStringSync(_emptyProjectLibrary);

      return new Terminal(projectDir);
    }

    try {
      temporaryDirectory.createSync();
    } catch (_) {}

    final creator = new Terminal(temporaryDirectory);

    final args = <String>[];
    if (template != null) {
      args.addAll(["-t", template]);
    }

    if (offline) {
      args.add("--offline");
    }

    args.add(name);

    await creator.runAqueductCommand("create", args);

    return new Terminal(new Directory.fromUri(temporaryDirectory.uri.resolve("$name/")));
  }

  static void deleteTemporaryDirectory() {
    try {
      temporaryDirectory.deleteSync(recursive: true);
    } catch (_) {}
  }

  Directory get migrationDirectory {
    return new Directory.fromUri(workingDirectory.uri.resolve("migrations/"));
  }

  Directory get libraryDirectory {
    return new Directory.fromUri(workingDirectory.uri.resolve("lib/"));
  }

  void addOrReplaceFile(String path, String contents, {bool importAqueduct: true}) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents = pathComponents.sublist(0, pathComponents.length - 1);
    final directory = new Directory.fromUri(
        relativeDirectoryComponents.fold(workingDirectory.uri, (Uri prev, elem) => prev.resolve(elem + "/")));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final file = new File.fromUri(directory.uri.resolve(pathComponents.last));
    file.writeAsStringSync("${importAqueduct ? "import 'package:aqueduct/aqueduct.dart';\n" : ""}" + contents);
  }

  void modifyFile(String path, String contents(String current)) {
    final pathComponents = path.split("/");
    final relativeDirectoryComponents = pathComponents.sublist(0, pathComponents.length - 1);
    final directory = new Directory.fromUri(
        relativeDirectoryComponents.fold(workingDirectory.uri, (Uri prev, elem) => prev.resolve(elem + "/")));
    final file = new File.fromUri(directory.uri.resolve(pathComponents.last));
    if (!file.existsSync()) {
      throw new ArgumentError("File at '${file.uri}' doesn't exist.");
    }

    final output = contents(file.readAsStringSync());
    file.writeAsStringSync(output);
  }

  Future<int> executeMigrations({String connectString: "postgres://dart:dart@localhost:5432/dart_test"}) {
    return runAqueductCommand("db", ["upgrade", "--connect", connectString]);
  }

  Future writeMigrations(List<Schema> schemas) async {
    try {
      migrationDirectory.createSync();
    } catch (_) {}
    var currentNumberOfMigrations =
        migrationDirectory
            .listSync()
            .where((e) => e.path.endsWith("migration.dart"))
            .length;

    for (var i = 1; i < schemas.length; i++) {
      var source = MigrationBuilder.sourceForSchemaUpgrade(schemas[i - 1], schemas[i], i);

      var file = new File.fromUri(migrationDirectory.uri.resolve("${i + currentNumberOfMigrations}.migration.dart"));
      file.writeAsStringSync(source);
    }
  }

  Future<ProcessResult> getDependencies({bool offline: true}) async {
    var args = ["get", "--no-packages-dir"];
    if (offline) {
      args.add("--offline");
    }

    var result = await Process
        .run("pub", args, workingDirectory: workingDirectory.absolute.path, runInShell: true)
        .timeout(new Duration(seconds: 20));

    if (result.exitCode != 0) {
      throw new Exception("${result.stderr}");
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

    var cmd = new Runner()
      ..outputSink = _output;
    var results = cmd.options.parse(args);

    final exitCode = await cmd.process(results);

    Directory.current = saved;

    return exitCode;
  }

  CLITask startAqueductCommand(String command, List<String> args) {
    args ??= [];
    args.insert(0, command);
    args.addAll(defaultAqueductArgs ?? []);

    print("Starting 'aqueduct ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = workingDirectory;

    var cmd = new Runner()
      ..outputSink = _output;
    var results = cmd.options.parse(args);

    final task = new CLITask();
    var elapsed = 0.0;
    final timer = new Timer.periodic(new Duration(milliseconds: 100), (t) {
      if (cmd.runningProcess != null) {
        t.cancel();
        Directory.current = saved;
        task.process = cmd.runningProcess;
        task._processStarted.complete(true);
      } else {
        elapsed += 100;
        if (elapsed > 30000) {
          Directory.current = saved;
          t.cancel();
          task._processStarted.completeError(new TimeoutException("Timed out after 30 seconds"));
        }
      }
    });

    cmd.process(results).then((exitCode) {
      if (!task._processStarted.isCompleted) {
        print("Command failed to start with exit code: $exitCode");
        timer.cancel();
        Directory.current = saved;
        task._processStarted.completeError(false);
        task._processFinished.complete(exitCode);
      } else {
        print("Command completed with exit code: $exitCode");
        task._processFinished.complete(exitCode);
      }
    });

    return task;
  }

  static final _emptyProjectPubspec = """
name: application_test
description: A web server application.
version: 0.0.1

environment:
  sdk: '>=1.20.0 <2.0.0'

dependencies:
  aqueduct:
    path: ../..

dev_dependencies:
  test: '>=0.12.0 <0.13.0'  
  """;

  static final _emptyProjectLibrary = """
export 'package:aqueduct/aqueduct.dart';
export 'channel.dart';  
  """;

  static final _emptyProjectChannel = """
import 'application_test.dart';
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
  StringBuffer collectedOutput = new StringBuffer();

  String get output => collectedOutput.toString();
}

class CLITask {
  StoppableProcess process;

  Future get hasStarted => _processStarted.future;
  Future<int> get exitCode => _processFinished.future;

  Completer<int> _processFinished = new Completer<int>();
  Completer<bool> _processStarted = new Completer<bool>();
}