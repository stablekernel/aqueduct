import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path_lib;
import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

import '../utilities/source_generator.dart';

import 'db.dart';
import 'setup.dart';
import 'create.dart';
import 'serve.dart';
import 'auth.dart';
import 'document.dart';

export 'db.dart';
export 'setup.dart';
export 'create.dart';
export 'serve.dart';
export 'auth.dart';
export 'document.dart';

/// Exceptions thrown by command line interfaces.
class CLIException {
  CLIException(this.message, {this.instructions});

  List<String> instructions;
  String message;

  String toString() => message;
}

enum CLIColor { red, green, blue, boldRed, boldGreen, boldBlue, boldNone, none }

abstract class CLIResultHandler {
  ArgResults values;
}

/// A command line interface command.
abstract class CLICommand implements CLIResultHandler {
  static const _Delimiter = "-- ";
  static const _Tabs = "    ";
  static const _ErrorDelimiter = "*** ";

  /// Options for this command.
  ArgParser options = new ArgParser(allowTrailingOptions: true)
    ..addOption("directory",
        abbr: "d",
        help: "Project directory to execute command in",
        defaultsTo: Directory.current.path)
    ..addFlag("help", abbr: "h", help: "Shows this", negatable: false)
    ..addFlag("stacktrace",
        help: "Shows the stacktrace if an error occurs", defaultsTo: false)
    ..addFlag("color",
        help: "Toggles ANSI color", negatable: true, defaultsTo: true);

  ArgResults values;
  bool get showColors => values["color"];
  bool get helpMeItsScary => values["help"];
  bool get showStacktrace => values["stacktrace"];
  Map<String, CLICommand> _commandMap = {};

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
  Future<int> process(ArgResults results,
      {List<String> parentCommandNames}) async {
    if (results.command != null) {
      if (parentCommandNames == null) {
        parentCommandNames = [name];
      } else {
        parentCommandNames.add(name);
      }
      return _commandMap[results.command.name]
          .process(results.command, parentCommandNames: parentCommandNames);
    }

    try {
      values = results;
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
      print("");
      if (showStacktrace) {
        displayError("Offending Stacktrace ***", color: CLIColor.red);
        print("$st");
      }
    } on IsolateExecutorException catch (e, st) {
      displayError(e.message);
      displayProgress("Try running 'pub get' first.");
      print("");

      if (showStacktrace) {
        displayError("Offending Stacktrace ***", color: CLIColor.red);
        print("$st");
      }
    } catch (e, st) {
      displayError("$e");
      print("");
      if (showStacktrace) {
        displayError("Offending Stacktrace ***", color: CLIColor.red);
        print("$st");
      }
    } finally {
      await cleanup();
    }
    return 1;
  }

  void displayError(String errorMessage,
      {bool showUsage: false, CLIColor color: CLIColor.boldRed}) {
    print(
        "${colorSymbol(color)}${_ErrorDelimiter}$errorMessage$defaultColorSymbol");
    if (showUsage) {
      print("\n${options.usage}");
    }
  }

  void displayInfo(String infoMessage, {CLIColor color: CLIColor.boldNone}) {
    print("${colorSymbol(color)}${_Delimiter}$infoMessage$defaultColorSymbol");
  }

  void displayProgress(String progressMessage,
      {CLIColor color: CLIColor.none}) {
    print("${colorSymbol(color)}${_Tabs}$progressMessage$defaultColorSymbol");
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
    print("${description}");
    print("${detailedDescription}");
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
      print("Available commands:");

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
}

abstract class CLIProject implements CLIResultHandler {
  String _packageName;

  Directory get projectDirectory => new Directory(values["directory"]).absolute;
  String get libraryName => packageName;
  String get packageName {
    if (_packageName == null) {
      var file = new File.fromUri(projectDirectory.uri.resolve("pubspec.yaml"));
      var yamlContents = file.readAsStringSync();
      var pubspec = loadYaml(yamlContents);

      _packageName = pubspec["name"];
    }

    return _packageName;
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

  Directory subdirectoryInProjectDirectory(String name,
      {bool createIfDoesNotExist: true}) {
    var dir = new Directory(name);
    if (path_lib.isRelative(name)) {
      dir = new Directory.fromUri(projectDirectory.uri.resolve(name));
    }

    if (createIfDoesNotExist && !dir.existsSync()) {
      dir.createSync();
    }

    return dir;
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

  Future<int> handle() async {
    printHelp();
    return 0;
  }

  String get name {
    return "aqueduct";
  }

  String get description {
    return "Aqueduct is a tool for managing Aqueduct applications.";
  }
}
