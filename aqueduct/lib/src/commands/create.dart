import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path_lib;
import 'package:pub_cache/pub_cache.dart';
import 'package:yaml/yaml.dart';

import 'base.dart';

/// Used internally.
class CLITemplateCreator extends CLICommand with CLIAqueductGlobal {
  CLITemplateCreator() {
    options
      ..addOption("template", abbr: "t", help: "Name of the template to use", defaultsTo: "default")
      ..addFlag("offline", negatable: false, help: "Will fetch dependencies from a local cache if they exist.");

    registerCommand(new CLITemplateList());
  }

  String get templateName => values["template"];

  String get projectName => values.rest.length > 0 ? values.rest.first : null;

  bool get offline => values["offline"];

  @override
  Future<int> handle() async {
    if (projectName == null) {
      printHelp(parentCommandName: "aqueduct");
      return 1;
    }

    if (!isSnakeCase(projectName)) {
      displayError("Invalid project name ($projectName is not snake_case).");
      return 1;
    }

    var destDirectory = destinationDirectoryFromPath(projectName);
    if (destDirectory.existsSync()) {
      displayError("${destDirectory.path} already exists, stopping.");
      return 1;
    }

    destDirectory.createSync();

    final templateSourceDirectory = new Directory.fromUri(getTemplateLocation(templateName));
    if (!templateSourceDirectory.existsSync()) {
      displayError("No template at ${templateSourceDirectory.path}.");
      return 1;
    }

    displayProgress("Template source is: ${templateSourceDirectory.path}");
    displayProgress("See more templates with 'aqueduct create list-templates'");
    copyProjectFiles(destDirectory, templateSourceDirectory, projectName);

    createProjectSpecificFiles(destDirectory.path);
    if (aqueductPackageRef.sourceType == "path") {
      final aqueductLocation = aqueductPackageRef.resolve().location;

      addDependencyOverridesToPackage(destDirectory.path,
          {"aqueduct": aqueductLocation.uri, "aqueduct_test": aqueductLocation.parent.uri.resolve("aqueduct_test/")});
    }

    displayInfo("Fetching project dependencies (pub get --no-packages-dir ${offline ? "--offline" : ""})...");
    displayInfo("Please wait...");
    try {
      await fetchProjectDependencies(destDirectory, offline: offline);
    } on TimeoutException {
      displayInfo("Fetching dependencies timed out. Run 'pub get' in your project directory.");
    }

    displayProgress("Success.");
    displayInfo("New project '$projectName' successfully created.");
    displayProgress("Project is located at ${destDirectory.path}");
    displayProgress("Open this directory in IntelliJ IDEA, Atom or VS Code.");
    displayProgress("See ${destDirectory.path}${path_lib.separator}README.md for more information.");

    return 0;
  }

  bool shouldIncludeItem(FileSystemEntity entity) {
    var ignoreFiles = [
      "packages",
      "pubspec.lock",
      "Dart_Packages.xml",
      "workspace.xml",
      "tasks.xml",
      "vcs.xml",
    ];

    var hiddenFilesToKeep = [".gitignore", ".travis.yml", ".analysis_options"];

    var lastComponent = entity.uri.pathSegments.last;
    if (lastComponent.length == 0) {
      lastComponent = entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
    }

    if (lastComponent.startsWith(".") && !hiddenFilesToKeep.contains(lastComponent)) {
      return false;
    }

    if (ignoreFiles.contains(lastComponent)) {
      return false;
    }

    return true;
  }

  void interpretContentFile(String projectName, Directory destinationDirectory, FileSystemEntity sourceFileEntity) {
    if (shouldIncludeItem(sourceFileEntity)) {
      if (sourceFileEntity is Directory) {
        copyDirectory(projectName, destinationDirectory, sourceFileEntity);
      } else {
        copyFile(projectName, destinationDirectory, sourceFileEntity);
      }
    }
  }

  void copyDirectory(String projectName, Directory destinationParentDirectory, Directory sourceDirectory) {
    var sourceDirectoryName = sourceDirectory.uri.pathSegments[sourceDirectory.uri.pathSegments.length - 2];
    var destDir = new Directory(path_lib.join(destinationParentDirectory.path, sourceDirectoryName));

    destDir.createSync();

    sourceDirectory.listSync().forEach((f) {
      interpretContentFile(projectName, destDir, f);
    });
  }

  void copyFile(String projectName, Directory destinationDirectory, File sourceFile) {
    var path = path_lib.join(destinationDirectory.path, fileNameForFile(projectName, sourceFile));
    var contents = sourceFile.readAsStringSync();

    contents = contents.replaceAll("wildfire", projectName);
    contents = contents.replaceAll("Wildfire", camelCaseFromSnakeCase(projectName));

    var outputFile = new File(path);
    outputFile.createSync();
    outputFile.writeAsStringSync(contents);
  }

  String fileNameForFile(String projectName, File sourceFile) {
    var fileName = sourceFile.uri.pathSegments.last;

    fileName = fileName.replaceFirst("wildfire", projectName);

    return fileName;
  }

  Directory destinationDirectoryFromPath(String pathString) {
    if (pathString.startsWith("/")) {
      return new Directory(pathString);
    }
    var currentDirPath = Directory.current.uri.toFilePath();
    if (!currentDirPath.endsWith(path_lib.separator)) {
      currentDirPath += path_lib.separator;
    }
    currentDirPath += pathString;

    return new Directory(currentDirPath);
  }

  void createProjectSpecificFiles(String directoryPath) {
    displayProgress("Generating config.yaml from config.src.yaml.");
    var configSrcPath = new File(path_lib.join(directoryPath, "config.src.yaml"));
    configSrcPath.copySync(new File(path_lib.join(directoryPath, "config.yaml")).path);
  }

  void addDependencyOverridesToPackage(String packageDirectoryPath, Map<String, Uri> overrides) {
    var pubspecFile = new File(path_lib.join(packageDirectoryPath, "pubspec.yaml"));
    var contents = pubspecFile.readAsStringSync();

    final overrideBuffer = new StringBuffer();
    overrideBuffer.writeln("dependency_overrides:");
    overrides.forEach((packageName, location) {
      overrideBuffer.writeln("  $packageName:");
      overrideBuffer.writeln("    path:  ${location.toFilePath(windows: Platform.isWindows)}");
    });

    pubspecFile.writeAsStringSync(contents + "\n$overrideBuffer");
  }

  void copyProjectFiles(Directory destinationDirectory, Directory sourceDirectory, String projectName) {
    displayInfo("Copying template files to new project directory (${destinationDirectory.path})...");
    try {
      destinationDirectory.createSync();

      new Directory(sourceDirectory.path).listSync().forEach((f) {
        displayProgress("Copying contents of ${f.path}");
        interpretContentFile(projectName, destinationDirectory, f);
      });
    } catch (e) {
      destinationDirectory.deleteSync(recursive: true);
      displayError("$e");
      rethrow;
    }
  }

  bool isSnakeCase(String string) {
    var expr = new RegExp("^[a-z][a-z0-9_]*\$");
    return expr.hasMatch(string);
  }

  String camelCaseFromSnakeCase(String string) {
    return string.split("_").map((str) {
      var firstChar = str.substring(0, 1);
      var remainingString = str.substring(1, str.length);
      return firstChar.toUpperCase() + remainingString;
    }).join("");
  }

  Future<int> fetchProjectDependencies(Directory workingDirectory, {bool offline: false}) async {
    var args = ["get", "--no-packages-dir"];
    if (offline) {
      args.add("--offline");
    }

    try {
      final cmd = Platform.isWindows ? "pub.bat" : "pub";
      var process = await Process
          .start(cmd, args, workingDirectory: workingDirectory.absolute.path, runInShell: true)
          .timeout(new Duration(seconds: 60));
      process.stdout.transform(utf8.decoder).listen((output) => outputSink?.write(output));
      process.stderr.transform(utf8.decoder).listen((output) => outputSink?.write(output));

      final exitCode = await process.exitCode;

      if (exitCode != 0) {
        throw new CLIException("If you are offline, try using `pub get --offline`.");
      }

      return exitCode;
    } on TimeoutException {
      displayError("Timed out fetching dependencies. Reconnect to the internet or use `pub get --offline`.");
      rethrow;
    }
  }

  @override
  String get usage {
    return super.usage + " <project_name>";
  }

  @override
  String get name {
    return "create";
  }

  @override
  String get detailedDescription {
    return "This command will use a template from the aqueduct package determined by either "
        "git-url (and git-ref), path-source or version. If none of these "
        "are specified, the most recent version on pub.dartlang.org is used.";
  }

  @override
  String get description {
    return "Creates Aqueduct applications from templates.";
  }
}

class CLITemplateList extends CLICommand with CLIAqueductGlobal {
  @override
  Future<int> handle() async {
    final templateRootDirectory = new Directory.fromUri(templateDirectory);
    final templateDirectories =
        await templateRootDirectory.list().where((fse) => fse is Directory).map((fse) => fse as Directory).toList();
    final templateDescriptions = await Future.wait(templateDirectories.map((dir) => _templateDescription(dir)));
    displayInfo("Available templates:");
    displayProgress("");

    for (final template in templateDescriptions) {
      displayProgress(template);
    }

    return 0;
  }

  @override
  String get name {
    return "list-templates";
  }

  @override
  String get description {
    return "List Aqueduct application templates.";
  }

  Future<String> _templateDescription(Directory templateDirectory) async {
    var name = templateDirectory.uri.pathSegments[templateDirectory.uri.pathSegments.length - 2];
    var pubspecContents = await (new File.fromUri(templateDirectory.uri.resolve("pubspec.yaml"))).readAsString();
    var pubspecDefinition = loadYaml(pubspecContents);

    return "$name | ${pubspecDefinition["description"]}";
  }
}

class CLIAqueductGlobal {
  PubCache pub = new PubCache();

  PackageRef get aqueductPackageRef {
    return pub.getGlobalApplications().firstWhere((app) => app.name == "aqueduct").getDefiningPackageRef();
  }

  Uri get templateDirectory {
    return aqueductPackageRef.resolve().location.uri.resolve("templates/");
  }

  Uri getTemplateLocation(String templateName) {
    return templateDirectory.resolve(templateName + "/");
  }
}
