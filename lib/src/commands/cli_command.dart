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


/// A command line interface command.
abstract class CLICommand {
  static const _Delimiter = "-- ";
  static const _Tabs = "    ";
  static const _ErrorDelimiter = "*** ";

  /// Options for this command.
  ArgParser get options;

  ArgResults values;
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

  void displayError(String errorMessage, {bool showUsage: false}) {
    print("${_ErrorDelimiter}$errorMessage");
    if (showUsage) {
      print("\n${options.usage}");
    }
  }

  void displayInfo(String infoMessage) {
    print("${_Delimiter}$infoMessage");
  }

  void displayProgress(String progressMessage) {
    print("${_Tabs}$progressMessage");
  }

  String getPackageNameFromDirectoryURI(Uri projectURI) {
    var file = new File.fromUri(projectURI.resolve("pubspec.yaml"));
    var yamlContents = file.readAsStringSync();
    var pubspec = loadYaml(yamlContents);

    return pubspec["name"];
  }
}
