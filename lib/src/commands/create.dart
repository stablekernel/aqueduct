import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path_lib;

import '../http/documentable.dart';
import 'base.dart';

/// Used internally.
class CLITemplateCreator extends CLICommand {
  CLITemplateCreator() {
    options
      ..addOption("template", abbr: "t", help: "Name of the template to use", defaultsTo: "default")
      ..addOption("template-directory", hide: true)
      ..addOption("git-url",
          help:
              "Git url, will trigger generating the template from the specified git repository instead of pub.")
      ..addOption("git-ref",
          defaultsTo: "master",
          help:
              "Git reference (branch or commit), will trigger generating the template from the git repository instead of pub.")
      ..addOption("path-source",
          help:
              "Full path on filesystem, will trigger generating the template from the aqueduct source at path-source instead of pub.")
      ..addOption("version",
          defaultsTo: "any",
          help: "Version string for aqueduct on pub for template source.")
      ..addFlag("offline",
          negatable: false,
          help: "Will fetch dependencies from a local cache if they exist.");
  }

  String get templateName => values["template"];
  String get templateDirectory => values["template-directory"];
  String get projectName => values.rest.length > 0 ? values.rest.first : null;
  String get gitURL => values["git-url"];
  String get gitRef => values["git-ref"];
  String get pathSource => values["path-source"];
  String get version => values["version"];
  bool get offline => values["offline"];

  Future<int> handle() async {
    if (projectName == null) {
      printHelp(parentCommandName: "aqueduct");
      return 1;
    }

    if (!isSnakeCase(projectName)) {
      displayError("Invalid project name (${projectName} is not snake_case).");
      return 1;
    }

    var destDirectory = destinationDirectoryFromPath(projectName);
    if (destDirectory.existsSync()) {
      displayError("${destDirectory.path} already exists, stopping.");
      return 1;
    }

    destDirectory.createSync();

    var aqueductPath = await determineAqueductPath(
        destDirectory, aqueductDependencyString,
        offline: offline);
    var sourceDirectory = new Directory(
        path_lib.join(aqueductPath, "example", "templates", templateName));

    if (templateDirectory != null) {
      sourceDirectory =
          new Directory(path_lib.join(templateDirectory, templateName));
    }

    if (!sourceDirectory.existsSync()) {
      displayError("No template at ${sourceDirectory.path}.");
      return 1;
    }

    displayProgress("Template source is: ${sourceDirectory.path}.");
    await copyProjectFiles(destDirectory, sourceDirectory, projectName);

    await createProjectSpecificFiles(
        destDirectory.path, aqueductDependencyString);

    await replaceAqueductDependencyString(
        destDirectory.path, aqueductDependencyString);

    displayInfo(
        "Fetching project dependencies (pub get --no-packages-dir ${offline ? "--offline" : ""})...");
    await runPubGet(destDirectory, offline: offline);

    displayProgress("Success.");
    displayInfo("New project '${projectName}' successfully created.");
    displayProgress("Project is located at ${destDirectory.path}");
    displayProgress("Open this directory in IntelliJ IDEA, Atom or VS Code.");
    displayProgress(
        "See ${destDirectory.path}${path_lib.separator}README.md for more information.");

    return 0;
  }

  Future<String> determineAqueductPath(
      Directory projectDirectory, String aqueductVersion,
      {bool offline: false}) async {
    var split = aqueductVersion.split("aqueduct:").last.trim();

    displayInfo("Fetching Aqueduct templates ($split)...");
    var temporaryPubspec = generatingPubspec(aqueductVersion);

    new File(path_lib.join(projectDirectory.path, "pubspec.yaml"))
        .writeAsStringSync(temporaryPubspec);

    await runPubGet(projectDirectory, offline: offline);

    var resolver = new PackagePathResolver(
        path_lib.join(projectDirectory.path, ".packages"));
    var resolvedURL =
        resolver.resolve(new Uri(scheme: "package", path: "aqueduct"));

    new File(path_lib.join(projectDirectory.path, "pubspec.yaml")).deleteSync();
    new File(path_lib.join(projectDirectory.path, ".packages")).deleteSync();

    var path = path_lib.normalize(resolvedURL + "..");
    displayProgress("Aqueduct directory is: ${path}");

    return path;
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
      lastComponent =
          entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
    }

    if (lastComponent.startsWith(".") &&
        !hiddenFilesToKeep.contains(lastComponent)) {
      return false;
    }

    if (ignoreFiles.contains(lastComponent)) {
      return false;
    }

    return true;
  }

  void interpretContentFile(String projectName, Directory destinationDirectory,
      FileSystemEntity sourceFileEntity) {
    if (shouldIncludeItem(sourceFileEntity)) {
      if (sourceFileEntity is Directory) {
        copyDirectory(projectName, destinationDirectory, sourceFileEntity);
      } else {
        copyFile(projectName, destinationDirectory, sourceFileEntity);
      }
    }
  }

  void copyDirectory(String projectName, Directory destinationParentDirectory,
      Directory sourceDirectory) {
    var sourceDirectoryName = sourceDirectory
        .uri.pathSegments[sourceDirectory.uri.pathSegments.length - 2];
    var destDir = new Directory(
        path_lib.join(destinationParentDirectory.path, sourceDirectoryName));

    destDir.createSync();

    sourceDirectory.listSync().forEach((f) {
      interpretContentFile(projectName, destDir, f);
    });
  }

  void copyFile(
      String projectName, Directory destinationDirectory, File sourceFile) {
    var path = path_lib.join(
        destinationDirectory.path, fileNameForFile(projectName, sourceFile));
    var contents = sourceFile.readAsStringSync();

    contents = contents.replaceAll("wildfire", projectName);
    contents =
        contents.replaceAll("Wildfire", camelCaseFromSnakeCase(projectName));

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

  String projectNameFromPath(String pathString) {
    var lastPathComponentIndex = pathString.lastIndexOf(path_lib.separator);
    var parentPath = pathString.substring(0, lastPathComponentIndex);
    var parentDirectory = new Directory(parentPath);
    if (!parentDirectory.existsSync()) {
      throw new CLIException("Path $parentPath does not exist.");
    }

    return pathString.substring(lastPathComponentIndex + 1);
  }

  Future createProjectSpecificFiles(
      String directoryPath, String aqueductVersion) async {
    displayProgress("Generating config.yaml from config.yaml.src.");
    var configSrcPath =
        new File(path_lib.join(directoryPath, "config.yaml.src"));
    configSrcPath
        .copySync(new File(path_lib.join(directoryPath, "config.yaml")).path);
  }

  Future replaceAqueductDependencyString(
      String destDirectoryPath, String aqueductVersion) async {
    var pubspecFile =
        new File(path_lib.join(destDirectoryPath, "pubspec.yaml"));
    var contents = pubspecFile.readAsStringSync();

    contents = contents.replaceFirst("aqueduct: \"^1.0.0\"", aqueductVersion);

    pubspecFile.writeAsStringSync(contents);
  }

  void copyProjectFiles(Directory destinationDirectory,
      Directory sourceDirectory, String projectName) {
    displayInfo(
        "Copying template files to new project directory (${destinationDirectory.path})...");
    try {
      destinationDirectory.createSync();

      new Directory(sourceDirectory.path).listSync().forEach((f) {
        displayProgress("Copying contents of ${f.path}");
        interpretContentFile(projectName, destinationDirectory, f);
      });
    } catch (e) {
      destinationDirectory.deleteSync(recursive: true);
      displayError("$e");
    }
  }

  String get aqueductDependencyString {
    var str = "aqueduct: ";
    if (gitURL != null) {
      str += "\n";
      str += "    git:\n";
      str += '      url: "$gitURL"\n';
      str += '      ref: "$gitRef"';
    } else if (pathSource != null) {
      str += "\n";
      str += "    path: $pathSource";
    } else {
      if (version == null) {
        str += "any";
      } else {
        str += '"$version"';
      }
    }
    return str;
  }

  String generatingPubspec(String aqueductDependencyString) {
    return 'name: aqueduct_generator\nversion: 1.0.0\nenvironment:\n  sdk: ">=1.16.0 <2.0.0"\ndependencies:\n  ' +
        aqueductDependencyString;
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

  Future<ProcessResult> runPubGet(Directory workingDirectory,
      {bool offline: false}) async {
    var args = ["get", "--no-packages-dir"];
    if (offline) {
      args.add("--offline");
    }

    try {
      var result = await Process
          .run("pub", args,
              workingDirectory: workingDirectory.absolute.path,
              runInShell: true)
          .timeout(new Duration(seconds: 20));

      if (result.exitCode != 0) {
        throw new CLIException(
            "${result.stderr}\n\nIf you are offline, try using --offline.");
      }

      return result;
    } on TimeoutException {
      displayError(
          "Timed out fetching dependencies. Reconnect to the internet or use --offline.");
      rethrow;
    }
  }

  String get usage {
    return super.usage + " <project_name>";
  }

  String get name {
    return "create";
  }

  String get detailedDescription {
    return "This command will use a template from the aqueduct package determined by either "
        "git-url (and git-ref), path-source or version. If none of these "
        "are specified, the most recent version on pub.dartlang.org is used.";
  }

  String get description {
    return "Creates Aqueduct applications from templates.";
  }

}
