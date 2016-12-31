import 'dart:async';
import 'dart:io';
import 'dart:mirrors';
import 'dart:isolate';

import 'package:yaml/yaml.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path_lib;

import '../http/http.dart';
import '../utilities/source_generator.dart';
import 'cli_command.dart';

class CLIServer extends CLICommand {
  CLIServer() {
    options
        ..addCommand("stop")
        ..addOption("sink", abbr: "s", help: "The name of the RequestSink subclass to be instantiated to serve requests. "
            "By default, this subclass is determined by reflecting on the application library in the [directory] being served.")
        ..addOption("directory", abbr: "d", help: "The directory that contains the application library to be served. "
            "Defaults to current working directory.")
        ..addOption("port", abbr: "p", help: "The port number to listen for HTTP requests on.", defaultsTo: "8080")
        ..addOption("address", abbr: "a",
            help: "The address to listen on. See HttpServer.bind for more details; this value is used as the String passed to InternetAddress.lookup."
                " Using the default will listen on any address.")
        ..addOption("config-path", abbr: "c", help: "The path to a configuration file. This File is available in the ApplicationConfiguration "
            "for a RequestSink to use to read application-specific configuration values. Relative paths are relative to [directory].",
            defaultsTo: "config.yaml")
        ..addOption("isolates", abbr: "n", help: "Number of isolates processing requests", defaultsTo: "3")
        ..addFlag("local", abbr: "l", help: "Overrides [address] to only accept connectiosn from local addresses.",
            negatable: false, defaultsTo: false)
        ..addFlag("ipv6-only", help: "Limits listening to IPv6 connections only.",
            negatable: false, defaultsTo: false)
        ..addFlag("observe", help: "Enables Dart Observatory", defaultsTo: false, negatable: false)
        ..addFlag("detached",
            help: "Runs the application detached from this script. This script will terminate and the application will continue executing",
            defaultsTo: false, negatable: false);
  }

  String packageName;
  String libraryName;
  String _derivedRequestSinkType;

  ArgResults get command => values.command;
  bool get shouldRunDetached => values["detached"];
  bool get shouldRunObservatory => values["observe"];
  bool get ipv6Only => values["ipv6-only"];
  bool get localOnly => values["local"];
  int get port => int.parse(values["port"]);
  int get numberOfIsolates => int.parse(values["isolates"]);
  String get address => values["address"];
  String get requestSinkType => values["sink"] ?? _derivedRequestSinkType;
  File get configurationFile {
    String path = values["config-path"];
    if (path_lib.isRelative(path)) {
      return _fileInProjectDirectory(path);
    }

    return new File(path);
  }
  Directory get directory {
    if (values["directory"] == null) {
      return Directory.current;
    }

    return new Directory(values["directory"]);
  }
  Directory get binDirectory => _subdirectoryInProjectDirectory("bin");
  List<FileSystemEntity> _registeredLaunchArtifacts = [];

  Future<int> handle() async {
    await _deriveApplicationLibraryDetails();

    if (command?.name == "stop") {
      return stop();
    }

    return start();
  }

  Future cleanup() async {
    _deleteLaunchArtifacts();
  }

  /////

  Future<int> start() async {
    await _prepare();

    if (!configurationFile.existsSync()) {
      displayError("Configuration file not found : ${configurationFile.path}");
      return 1;
    }

    var replacements = {
      "PACKAGE_NAME" : packageName,
      "LIBRARY_NAME": libraryName,
      "SINK_TYPE": requestSinkType,
      "PORT": port,
      "ADDRESS": address,
      "IPV6_ONLY": ipv6Only,
      "NUMBER_OF_ISOLATES": numberOfIsolates,
      "CONFIGURATION_FILE_PATH": configurationFile.path
    };

    displayInfo("Starting application '$packageName/$libraryName'");
    displayProgress("Sink Type: $requestSinkType");
    displayProgress("Config: ${configurationFile.path}");

    var startupTime = new DateTime.now();
    var generatedStartScript = _createScriptSource(replacements);
    var startScriptFile = _createStartScript(generatedStartScript);
    var serverProcess = await _executeStartScript(startScriptFile);
    var startFailureReason = await _checkForStartError(serverProcess);

    if (startFailureReason != "ok") {
      _failWithError(serverProcess.pid, startFailureReason);
      return 1;
    }

    var now = new DateTime.now();
    var diff = now.difference(startupTime);
    displayInfo("Success!", color: CLIColor.boldGreen);
    displayProgress("Startup Time: ${diff.inSeconds}.${"${diff.inMilliseconds}".padLeft(4, "0")}s");
    displayProgress("Application '$packageName/$libraryName' now running on port $port. (PID: ${serverProcess.pid})");
    if (!shouldRunDetached) {
      displayProgress("Use Ctrl-C (SIGINT) to stop running the application.");
      displayInfo("Starting Application Log --");
      stdout.addStream(serverProcess.stdout);

      var cleanupFile = (ProcessSignal s) {
        var f = new File(_pidPathForPid(serverProcess.pid));
        if (f.existsSync()) {
          f.deleteSync();
        }

        Isolate.current.kill();
      };
      ProcessSignal.SIGINT.watch().listen(cleanupFile);
    } else {
      displayProgress("Use 'aqueduct serve stop' in '${directory.path}' to stop running the application.");
    }

    return 0;
  }

  Future<int> stop() async {
    displayInfo("Stopping application.");
    _pidFilesInDirectory(directory)
        .forEach((file) {
          var pidString = path_lib.relative(file.path, from: directory.path)
              .split(".")[1];
          _stopPidAndDelete(int.parse(pidString));
        });

    displayInfo("Application stopped.");
    return 0;
  }

  Future<Process> _executeStartScript(File startScriptFile) async {
    var args = <String>[];
    if (shouldRunObservatory) {
      args.add("--observe");
    }
    args.add(startScriptFile.absolute.path);

    var startMode = ProcessStartMode.NORMAL;
    if (shouldRunDetached) {
      startMode = ProcessStartMode.DETACHED;
    }

    displayProgress("Starting process...");
    var process = await Process.start("dart", args,
        workingDirectory: directory.absolute.path,
        runInShell: true,
        mode: startMode);

    if (!shouldRunDetached) {
      stderr.addStream(process.stderr);
      process.exitCode.then((code) {
        displayError("Server terminated (Exit Code: $code)");
        exit(0);
      });
    }

    return process;
  }

  void _failWithError(int processPid, String reason) {
    displayError("Application failed to start: \n\n$reason");
    Process.killPid(processPid);

    var processFile = new File.fromUri(directory.uri.resolve(_pidPathForPid(processPid)));
    try {
      processFile.deleteSync();
    } catch (_) {}
  }

  Future<String> _checkForStartError(Process process) async {
    displayProgress("Verifying launch...");

    int timeoutInMilliseconds = 20 * 1000;
    var completer = new Completer<String>();
    var accumulated = 0;

    new Timer.periodic(new Duration(milliseconds: 100), (t) {
      var signalFile = _fileInProjectDirectory(_pidPathForPid(process.pid));
      if (signalFile.existsSync()) {
        t.cancel();
        completer.complete(signalFile.readAsStringSync());
      }
      accumulated += 100;

      if (accumulated >= timeoutInMilliseconds) {
        t.cancel();
        completer.completeError(new CLIException("Timed out waiting for application start."));
      }
    });

    return completer.future;
  }

  File _createStartScript(String contents) {
    var filename = ".tmp_aqueduct_serve_start.dart";
    var file = new File.fromUri(binDirectory.uri.resolve(filename));

    file.writeAsStringSync(contents);

    _registeredLaunchArtifacts.add(file);

    return file;
  }

  Future _deriveApplicationLibraryDetails() async {
    // Find packageName, libraryName and _derivedRequestSinkType
    var pubspecFile = _fileInProjectDirectory("pubspec.yaml");
    if (!pubspecFile .existsSync()) {
      throw new CLIException("$pubspecFile  does not exist.");
    }

    var pubspecContents = loadYaml(pubspecFile .readAsStringSync());
    var name = pubspecContents["name"];

    packageName = name;
    libraryName = name;

    var generator = new SourceGenerator(
            (List<String> args, Map<String, dynamic> values) async {
              var sinkType = reflectClass(RequestSink);
              var classes = currentMirrorSystem()
                  .libraries
                  .values
                  .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
                  .expand((lib) => lib.declarations.values)
                  .where((decl) =>
                    decl is ClassMirror && decl.isSubclassOf(sinkType))
                  .map((decl) => decl as ClassMirror)
                  .toList();

            return classes
                .map((cm) => MirrorSystem.getName(cm.simpleName))
                .first;
        }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$packageName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        packageConfigURI: directory.uri.resolve(".packages"));
    _derivedRequestSinkType = await executor.execute(workingDirectory: directory.uri);
  }

  Future _prepare() async {
    displayInfo("Preparing...");
    await Future.wait(_pidFilesInDirectory(directory)
        .map((FileSystemEntity f) {
          var pidString = path_lib.relative(f.path, from: directory.path)
            .split(".")[1];

          displayProgress("Stopping currently running server (PID: $pidString)");

          return _stopPidAndDelete(int.parse(pidString));
        }));
  }

  List<File> _pidFilesInDirectory(Directory directory) {
    return directory
        .listSync()
        .where((fse) {
      return fse is File && fse.path.endsWith(_pidSuffix);
    })
        .toList();
  }

  String _createScriptSource(Map<String, dynamic> values) {
    var addressString = "..address = \"___ADDRESS___\"";
    if (values["ADDRESS"] == null) {
      addressString = "";
    }

    var contents = """
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:___PACKAGE_NAME___/___LIBRARY_NAME___.dart';

main() async {
  try {
    var app = new Application<___SINK_TYPE___>();
    var config = new ApplicationConfiguration()
      ..port = ___PORT___
      $addressString
      ..configurationFilePath = \"___CONFIGURATION_FILE_PATH___\"
      ..isIpv6Only = ___IPV6_ONLY___;

    app.configuration = config;

    await app.start(numberOfInstances: ___NUMBER_OF_ISOLATES___);

    var signalFile = new File(".\${pid}.$_pidSuffix");
    await signalFile.writeAsString("ok");
  } catch (e, st) {
    await writeError("\$e\\n \$st");
  }
}

Future writeError(String error) async {
  var signalFile = new File(".\${pid}.$_pidSuffix");
  await signalFile.writeAsString(error);
}
    """;

    return contents.replaceAllMapped(new RegExp("___([A-Za-z0-9_-]+)___"), (match) {
      return values[match.group(1)];
    });
  }

  void _deleteLaunchArtifacts() {
    _registeredLaunchArtifacts.forEach((e) {
      e.deleteSync();
    });
  }

  File _fileInProjectDirectory(String name) {
    return new File.fromUri(directory.uri.resolve(name));
  }

  Directory _subdirectoryInProjectDirectory(String name, {bool createIfDoesNotExist: true}) {
    var dir = new Directory.fromUri(directory.uri.resolve(name));
    if (createIfDoesNotExist && !dir.existsSync()) {
      dir.createSync();
    }

    return dir;
  }

  Future _stopPidAndDelete(int pid) async {
    var file = _fileInProjectDirectory(_pidPathForPid(pid));
    Process.killPid(pid);
    file.deleteSync();

    displayProgress("Stopped PID $pid.");
  }

  static const String _pidSuffix = "aqueduct.pid";
  String _pidPathForPid(int pid) {
    return ".$pid.$_pidSuffix";
  }
}