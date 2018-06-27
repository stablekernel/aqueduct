import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:aqueduct/src/commands/running_process.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path_lib;
import 'package:yaml/yaml.dart';
import 'package:pub_semver/pub_semver.dart';

import 'auth.dart';
import 'create.dart';
import 'db.dart';
import 'document.dart';
import 'serve.dart';
import 'setup.dart';

export 'auth.dart';
export 'create.dart';
export 'db.dart';
export 'document.dart';
export 'serve.dart';
export 'setup.dart';

/// Exceptions thrown by command line interfaces.
class CLIException {
  CLIException(this.message, {this.instructions});

  final List<String> instructions;
  final String message;

  @override
  String toString() => message;
}

enum CLIColor { red, green, blue, boldRed, boldGreen, boldBlue, boldNone, none }

/// A command line interface command.
abstract class CLICommand {
  static const _Delimiter = "-- ";
  static const _Tabs = "    ";
  static const _ErrorDelimiter = "*** ";

  /// Options for this command.
  ArgParser options = new ArgParser(allowTrailingOptions: true)
    ..addFlag("version", help: "Prints version of this tool", negatable: false)
    ..addOption("directory",
        abbr: "d", help: "Project directory to execute command in", defaultsTo: Directory.current.path)
    ..addFlag("help", abbr: "h", help: "Shows this", negatable: false)
    ..addFlag("machine",
        help: "Output is machine-readable, usable for creating tools on top of this CLI. Behavior varies by command.",
        defaultsTo: false)
    ..addFlag("stacktrace", help: "Shows the stacktrace if an error occurs", defaultsTo: false)
    ..addFlag("color", help: "Toggles ANSI color", negatable: true, defaultsTo: true);

  ArgResults _argumentValues;
  List<String> get remainingArguments => _argumentValues.rest;
  ArgResults get command => _argumentValues.command;

  StoppableProcess get runningProcess {
    return _commandMap.values.firstWhere((cmd) => cmd.runningProcess != null, orElse: () => null)?.runningProcess;
  }

  bool get showVersion => decode("version");

  bool get showColors => decode("color");

  bool get helpMeItsScary => decode("help");

  bool get showStacktrace => decode("stacktrace");

  bool get isMachineOutput => decode("machine");

  Map<String, CLICommand> _commandMap = {};

  StringSink _outputSink = stdout;

  StringSink get outputSink => _outputSink;

  set outputSink(StringSink sink) {
    _outputSink = sink;
    _commandMap.values.forEach((cmd) {
      cmd.outputSink = sink;
    });
  }

  Version get toolVersion => _toolVersion;
  Version _toolVersion;

  T decode<T>(String key) {
    final val = _argumentValues[key];
    if (T == int && val is String) {
      return int.parse(val) as T;
    }
    return runtimeCast(val, reflectType(T)) as T;
  }

  void registerCommand(CLICommand cmd) {
    _commandMap[cmd.name] = cmd;
    options.addCommand(cmd.name, cmd.options);
  }

  /// Handles the command input.
  ///
  /// Override this method to perform actions for this command.
  ///
  /// Return value is the value returned to the command line operation. Return 0 for success.
  Future<int> handle();

  /// Cleans up any resources used during this command.
  ///
  /// Delete temporary files or close down any [Stream]s.
  Future cleanup() async {}

  /// Invoked on this instance when this command is executed from the command line.
  ///
  /// Do not override this method. This method invokes [handle] within a try-catch block
  /// and will invoke [cleanup] when complete.
  Future<int> process(ArgResults results, {List<String> parentCommandNames}) async {
    if (results.command != null) {
      if (parentCommandNames == null) {
        parentCommandNames = [name];
      } else {
        parentCommandNames.add(name);
      }
      return _commandMap[results.command.name].process(results.command, parentCommandNames: parentCommandNames);
    }

    try {
      _argumentValues = results;

      await determineToolVersion();

      if (showVersion) {
        outputSink.writeln("Aqueduct CLI version: $toolVersion");
        return 0;
      }

      if (!isMachineOutput) {
        displayInfo("Aqueduct CLI Version: $toolVersion");
      }

      preProcess();

      if (helpMeItsScary) {
        printHelp(parentCommandName: parentCommandNames?.join(" "));
        return 0;
      }

      return await handle();
    } on CLIException catch (e, st) {
      displayError(e.message);
      e.instructions?.forEach((instruction) {
        displayProgress(instruction);
      });

      if (showStacktrace) {
        printStackTrace(st);
      }
    } catch (e, st) {
      displayError("Uncaught error");
      displayProgress("$e");
      printStackTrace(st);
    } finally {
      await cleanup();
    }
    return 1;
  }

  Future determineToolVersion() async {
    try {
      var toolLibraryFilePath = (await Isolate.resolvePackageUri(currentMirrorSystem().findLibrary(#aqueduct).uri))
          .toFilePath(windows: Platform.isWindows);
      var aqueductDirectory = new Directory(FileSystemEntity.parentOf(FileSystemEntity.parentOf(toolLibraryFilePath)));
      var toolPubspecFile = new File.fromUri(aqueductDirectory.absolute.uri.resolve("pubspec.yaml"));

      Map toolPubspecContents = loadYaml(toolPubspecFile.readAsStringSync());
      String toolVersion = toolPubspecContents["version"];
      _toolVersion = new Version.parse(toolVersion);
    } catch (e) {
      print(e);
    }
  }

  void preProcess() {}

  void displayError(String errorMessage, {bool showUsage: false, CLIColor color: CLIColor.boldRed}) {
    outputSink.writeln("${colorSymbol(color)}$_ErrorDelimiter$errorMessage$defaultColorSymbol");
    if (showUsage) {
      outputSink.writeln("\n${options.usage}");
    }
  }

  void displayInfo(String infoMessage, {CLIColor color: CLIColor.boldNone}) {
    outputSink.writeln("${colorSymbol(color)}$_Delimiter$infoMessage$defaultColorSymbol");
  }

  void displayProgress(String progressMessage, {CLIColor color: CLIColor.none}) {
    outputSink.writeln("${colorSymbol(color)}$_Tabs$progressMessage$defaultColorSymbol");
  }

  String colorSymbol(CLIColor color) {
    if (!showColors) {
      return "";
    }
    return _lookupTable[color];
  }

  String get name;

  String get detailedDescription => "";

  String get usage {
    var buf = new StringBuffer(name);
    if (_commandMap.length > 0) {
      buf.write(" <command>");
    }
    buf.write(" [arguments]");
    return buf.toString();
  }

  String get description;

  String get defaultColorSymbol {
    if (!showColors) {
      return "";
    }
    return "\u001b[0m";
  }

  static const Map<CLIColor, String> _lookupTable = const {
    CLIColor.red: "\u001b[31m",
    CLIColor.green: "\u001b[32m",
    CLIColor.blue: "\u001b[34m",
    CLIColor.boldRed: "\u001b[31;1m",
    CLIColor.boldGreen: "\u001b[32;1m",
    CLIColor.boldBlue: "\u001b[34;1m",
    CLIColor.boldNone: "\u001b[0;1m",
    CLIColor.none: "\u001b[0m",
  };

  void printHelp({String parentCommandName}) {
    print("$description");
    print("$detailedDescription");
    print("");
    if (parentCommandName == null) {
      print("Usage: $usage");
    } else {
      print("Usage: $parentCommandName $usage");
    }
    print("");
    print("Options:");
    print("${options.usage}");

    if (options.commands.length > 0) {
      print("Available sub-commands:");

      var commandNames = options.commands.keys.toList();
      commandNames.sort((a, b) => b.length.compareTo(a.length));
      var length = commandNames.first.length + 3;
      commandNames.forEach((command) {
        var desc = _commandMap[command]?.description;
        print("  ${command.padRight(length, " ")}$desc");
      });
    }
  }

  bool isExecutableInShellPath(String name) {
    String locator = Platform.isWindows ? "where" : "which";
    ProcessResult results = Process.runSync(locator, [name], runInShell: true);

    return results.exitCode == 0;
  }

  void printStackTrace(StackTrace st) {
    outputSink.writeln("  **** Stacktrace");
    st.toString().split("\n").forEach((line) {
      if (line.isEmpty) {
        outputSink.writeln("  ****");
      } else {
        outputSink.writeln("  * $line");
      }
    });
  }
}

abstract class CLIProject implements CLICommand {
  Map<String, dynamic> _pubspec;

  Map<String, dynamic> get projectSpecification {
    if (_pubspec == null) {
      final file = projectSpecificationFile;
      if (!file.existsSync()) {
        throw new CLIException("Failed to locate pubspec.yaml in project directory '${projectDirectory.path}'");
      }
      var yamlContents = file.readAsStringSync();
      final Map<dynamic, dynamic> yaml = loadYaml(yamlContents);
      _pubspec = yaml.cast<String, dynamic>();
    }

    return _pubspec;
  }

  File get projectSpecificationFile => new File.fromUri(projectDirectory.uri.resolve("pubspec.yaml"));

  Directory get projectDirectory => new Directory(decode("directory")).absolute;

  Uri get packageConfigUri => projectDirectory.uri.resolve(".packages");

  String get libraryName => packageName;

  String get packageName => projectSpecification["name"];

  Version _projectVersion;

  Version get projectVersion {
    if (_projectVersion == null) {
      var lockFile = new File.fromUri(projectDirectory.uri.resolve("pubspec.lock"));
      if (!lockFile.existsSync()) {
        throw new CLIException("No pubspec.lock file. Run `pub get`.");
      }

      Map lockFileContents = loadYaml(lockFile.readAsStringSync());
      String projectVersion = lockFileContents["packages"]["aqueduct"]["version"];
      _projectVersion = new Version.parse(projectVersion);
    }

    return _projectVersion;
  }

  static File fileInDirectory(Directory directory, String name) {
    if (path_lib.isRelative(name)) {
      return new File.fromUri(directory.uri.resolve(name));
    }

    return new File.fromUri(directory.uri);
  }

  File fileInProjectDirectory(String name) {
    return fileInDirectory(projectDirectory, name);
  }

  @override
  void preProcess() {
    if (!isMachineOutput) {
      try {
        displayInfo("Aqueduct project version: $projectVersion");
      } catch (_) {} // Ignore if this doesn't succeed.
    }
  }
}

class Runner extends CLICommand {
  Runner() {
    registerCommand(new CLITemplateCreator());
    registerCommand(new CLIDatabase());
    registerCommand(new CLIServer());
    registerCommand(new CLISetup());
    registerCommand(new CLIAuth());
    registerCommand(new CLIDocument());
  }

  @override
  bool get showVersion => decode("version");

  @override
  Future<int> handle() async {
    printHelp();
    return 0;
  }

  @override
  String get name {
    return "aqueduct";
  }

  @override
  String get description {
    return "Aqueduct is a tool for managing Aqueduct applications.";
  }
}
