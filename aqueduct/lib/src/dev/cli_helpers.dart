import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/runner.dart';
import 'package:aqueduct/src/cli/running_process.dart';

import 'package:command_line_agent/command_line_agent.dart';

class CLIClient {
  CLIClient(this.agent);

  final CommandLineAgent agent;

  ProjectAgent get projectAgent {
    if (agent is ProjectAgent) {
      return agent as ProjectAgent;
    }

    throw StateError("is not a project terminal");
  }
  List<String> defaultArgs;

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

  Directory get defaultMigrationDirectory {
    return Directory.fromUri(agent.workingDirectory.uri.resolve("migrations/"));
  }

  Directory get libraryDirectory {
    return Directory.fromUri(agent.workingDirectory.uri.resolve("lib/"));
  }

  void delete() {
    agent.workingDirectory.deleteSync(recursive: true);
  }

  CLIClient replicate(Uri uri) {
    var dstUri = uri;
    if (!uri.isAbsolute) {
      dstUri = ProjectAgent.projectsDirectory.uri.resolveUri(uri);
    }

    final dstDirectory = Directory.fromUri(dstUri);
    if (dstDirectory.existsSync()) {
      dstDirectory.deleteSync(recursive: true);
    }
    CommandLineAgent.copyDirectory(src: agent.workingDirectory.uri, dst: dstUri);
    return CLIClient(ProjectAgent.existing(dstUri));
  }

  void clearOutput() {
    _output.clear();
  }

  Future<CLIClient> createProject(
      {String name = "application_test",
      String template,
      bool offline = true}) async {
    if (template == null) {
      final client = CLIClient(ProjectAgent(name, dependencies: {
        "aqueduct" : {
          "path": "../.."
        }
      }, devDependencies: {
        "test": "^1.0.0"
      }));
      
      client.projectAgent.addLibraryFile("channel", """
import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

import '$name.dart';

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
  """);
      
      return client;
    }
    
    try {
      ProjectAgent.projectsDirectory.createSync();
    } catch (_) {}

    final args = <String>[];
    if (template != null) {
      args.addAll(["-t", template]);
    }

    if (offline) {
      args.add("--offline");
    }

    args.add(name);

    await run("create", args);
    print("$output");

    return CLIClient(ProjectAgent.existing(ProjectAgent.projectsDirectory.uri.resolve("$name/")));
  }

  Future<int> executeMigrations(
      {String connectString =
          "postgres://dart:dart@localhost:5432/dart_test"}) async {
    final res =
        await run("db", ["upgrade", "--connect", connectString]);
    if (res != 0) {
      print("executeMigrations failed: $output");
    }
    return res;
  }

  Future<List<File>> writeMigrations(List<Schema> schemas) async {
    try {
      defaultMigrationDirectory.createSync();
    } catch (_) {}

    final currentNumberOfMigrations = defaultMigrationDirectory
        .listSync()
        .where((e) => e.path.endsWith("migration.dart"))
        .length;

    final files = <File>[];
    for (var i = 1; i < schemas.length; i++) {
      var source =
          Migration.sourceForSchemaUpgrade(schemas[i - 1], schemas[i], i);

      var file = File.fromUri(defaultMigrationDirectory.uri
          .resolve("${i + currentNumberOfMigrations}.migration.dart"));
      file.writeAsStringSync(source);
      files.add(file);
    }

    return files;
  }

  Future<int> run(String command, [List<String> args]) async {
    args ??= [];
    args.insert(0, command);
    args.addAll(defaultArgs ?? []);

    print("Running 'aqueduct ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = agent.workingDirectory;

    var cmd = Runner()..outputSink = _output;
    var results = cmd.options.parse(args);

    final exitCode = await cmd.process(results);
    if (exitCode != 0) {
      print("command failed: ${output}");
    }

    Directory.current = saved;

    return exitCode;
  }

  CLITask start(String command, List<String> inputArgs) {
    final args = inputArgs ?? [];
    args.insert(0, command);
    args.addAll(defaultArgs ?? []);

    print("Starting 'aqueduct ${args.join(" ")}'");
    final saved = Directory.current;
    Directory.current = agent.workingDirectory;

    var cmd = Runner()..outputSink = _output;
    var results = cmd.options.parse(args);

    final task = CLITask();
    var elapsed = 0.0;
    final timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
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
