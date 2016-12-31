import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:yaml/yaml.dart';

export 'migration_runner.dart';
export 'setup_command.dart';
export 'template_creator.dart';
export 'serve.dart';

/// Exceptions thrown by command line interfaces.
class CLIException {
  CLIException(this.message);

  String message;

  String toString() => message;
}

enum CLIColor { red, green, blue, boldRed, boldGreen, boldBlue, boldNone, none }

/// A command line interface command.
abstract class CLICommand {
  static const _Delimiter = "-- ";
  static const _Tabs = "    ";
  static const _ErrorDelimiter = "*** ";

  /// Options for this command.
  ArgParser options = new ArgParser()
    ..addFlag("help", abbr: "h", help: "Shows this", negatable: false)
    ..addFlag("color",
        help: "Toggles ANSI color", negatable: true, defaultsTo: true);

  ArgResults values;
  bool get showColors => values["color"] ?? true;
  bool get helpMeItsScary {
    if (values != null) {
      return values["help"] ?? false;
    }
    return false;
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
  Future<int> process(ArgResults results) async {
    try {
      values = results;

      if (helpMeItsScary) {
        print("${options.usage}");
        return 0;
      }

      return await handle();
    } catch (e, st) {
      displayError("$e\n$st");
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

  String getPackageNameFromDirectoryURI(Uri projectURI) {
    var file = new File.fromUri(projectURI.resolve("pubspec.yaml"));
    var yamlContents = file.readAsStringSync();
    var pubspec = loadYaml(yamlContents);

    return pubspec["name"];
  }

  String colorSymbol(CLIColor color) {
    if (!showColors) {
      return "";
    }
    return _lookupTable[color];
  }

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
}
