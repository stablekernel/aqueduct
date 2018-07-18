import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as path_lib;

abstract class CLIProject implements CLICommand {
  @Option("directory",
      abbr: "d", help: "Project directory to execute command in")
  Directory get projectDirectory {
    if (_projectDirectory == null) {
      String dir = decode("directory");
      if (dir == null) {
        _projectDirectory = Directory.current.absolute;
      } else {
        _projectDirectory = Directory(dir).absolute;
      }
    }
    return _projectDirectory;
  }

  Map<String, dynamic> get projectSpecification {
    if (_pubspec == null) {
      final file = projectSpecificationFile;
      if (!file.existsSync()) {
        throw CLIException(
            "Failed to locate pubspec.yaml in project directory '${projectDirectory.path}'");
      }
      var yamlContents = file.readAsStringSync();
      final Map<dynamic, dynamic> yaml = loadYaml(yamlContents);
      _pubspec = yaml.cast<String, dynamic>();
    }

    return _pubspec;
  }

  File get projectSpecificationFile =>
      File.fromUri(projectDirectory.uri.resolve("pubspec.yaml"));

  Uri get packageConfigUri => projectDirectory.uri.resolve(".packages");

  String get libraryName => packageName;

  String get packageName => projectSpecification["name"] as String;

  Version get projectVersion {
    if (_projectVersion == null) {
      var lockFile = File.fromUri(projectDirectory.uri.resolve("pubspec.lock"));
      if (!lockFile.existsSync()) {
        throw CLIException("No pubspec.lock file. Run `pub get`.");
      }

      Map lockFileContents = loadYaml(lockFile.readAsStringSync());
      String projectVersion =
          lockFileContents["packages"]["aqueduct"]["version"];
      _projectVersion = Version.parse(projectVersion);
    }

    return _projectVersion;
  }

  Directory _projectDirectory;
  Map<String, dynamic> _pubspec;
  Version _projectVersion;

  static File fileInDirectory(Directory directory, String name) {
    if (path_lib.isRelative(name)) {
      return File.fromUri(directory.uri.resolve(name));
    }

    return File.fromUri(directory.uri);
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
