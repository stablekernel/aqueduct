part of aqueduct;

class TemplateCreator extends CLICommand {
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("template", abbr: "t", defaultsTo: "default", help: "Name of the template. Defaults to default. Available options are: default")
    ..addOption("name", abbr: "n", help: "Name of project in snake_case.")
    ..addOption("template-directory", hide: true)
    ..addOption("git-url", help: "Git url, will trigger generating the template from the specified git repository instead of pub.")
    ..addOption("git-ref", defaultsTo: "master", help: "Git reference (branch or commit), will trigger generating the template from the git repository instead of pub.")
    ..addOption("path-source", help: "Full path on filesystem, will trigger generating the template from the aqueduct source at path-source instead of pub.")
    ..addOption("version", defaultsTo: "any", help: "Version string for aqueduct on pub for template source.")
    ..addFlag("help", negatable: false, help: "Shows this documentation");

  Future<int> handle(ArgResults argValues) async {
    if (argValues["help"] == true) {
      print("${options.usage}");
      return 0;
    }

    if (argValues["name"] == null || !isSnakeCase(argValues["name"])) {
      print("Invalid project name\n\n${options.usage}");
      return -1;
    }

    var destDirectory = destinationDirectoryFromPath(argValues["name"]);
    if (destDirectory.existsSync()) {
      print("${destDirectory.path} already exists.");
      return -1;
    }
    destDirectory.createSync();

    var aqueductVersion = aqueductDependencyString(versionString: argValues["version"], gitHost: argValues["git-url"], gitRef: argValues["git-ref"], path: argValues["path-source"]);

    print("Fetching template source...");
    var aqueductPath = await determineAqueductPath(destDirectory, aqueductVersion);
    var sourceDirectory = new Directory("${aqueductPath}/example/templates/${argValues["template"]}");

    if (argValues["template-directory"] != null) {
      sourceDirectory = new Directory("${argValues["template-directory"]}/${argValues["template"]}");
    }
    if (!sourceDirectory.existsSync()) {
      print("Error: no template named ${argValues["template"]}");
      return -1;
    }

    print("Copying project files...");
    await copyProjectFiles(destDirectory, sourceDirectory, argValues["name"]);

    print("Generating project files...");
    await createProjectSpecificFiles(destDirectory.path, aqueductVersion);

    print("Fetching dependencies...");
    Process.runSync("pub", ["get"], workingDirectory: destDirectory.path);

    print("${argValues["name"]} created at ${destDirectory.path}");
    print("Make sure to follow the instructions in ${destDirectory.path}/README.md to be able to run your project!");

    return 0;
  }


  String determineAqueductPath(Directory projectDirectory, String aqueductVersion) {
    var temporaryPubspec = generatingPubspec(aqueductVersion);

    new File(projectDirectory.path + "/pubspec.yaml").writeAsStringSync(temporaryPubspec);
    var result = Process.runSync("pub", ["get"], workingDirectory: projectDirectory.path);
    if (result.exitCode != 0) {
      throw new Exception("${result.stderr}");
    }

    var resolver = new PackagePathResolver(projectDirectory.path + "/.packages");
    var resolvedURL = resolver.resolve(new Uri(scheme: "package", path: "aqueduct"));

    new File(projectDirectory.path + "/pubspec.yaml").deleteSync();
    new File(projectDirectory.path + "/.packages").deleteSync();

    var lastLibIndex = resolvedURL.lastIndexOf("/lib");
    return resolvedURL.substring(0, lastLibIndex);
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

    var hiddenFilesToKeep = [
      ".gitignore",
      ".travis.yml",
      ".analysis_options"
    ];

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
    var destDir = new Directory(destinationParentDirectory.path + "/" + sourceDirectoryName);

    destDir.createSync();

    sourceDirectory.listSync().forEach((f) {
      interpretContentFile(projectName, destDir, f);
    });
  }

  void copyFile(String projectName, Directory destinationDirectory, File sourceFile) {
    var path = destinationDirectory.path + "/" + fileNameForFile(projectName, sourceFile);
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
    if (!currentDirPath.endsWith("/")) {
      currentDirPath += "/";
    }
    currentDirPath += pathString;

    return new Directory(currentDirPath);
  }

  String projectNameFromPath(String pathString) {
    var lastPathComponentIndex = pathString.lastIndexOf("/");
    var parentPath = pathString.substring(0, lastPathComponentIndex);
    var parentDirectory = new Directory(parentPath);
    if (!parentDirectory.existsSync()) {
      throw new Exception("Error: path $parentPath does not exist.");
    }

    return pathString.substring(lastPathComponentIndex + 1);
  }

  Future createProjectSpecificFiles(String directoryPath, String aqueductVersion) async {
    var configSrcPath = new File(directoryPath + "/config.yaml.src");
    configSrcPath.copySync(new File(directoryPath + "/config.yaml").path);

    var pubspecContents = new File(directoryPath + "/pubspec.yaml").readAsStringSync();
    pubspecContents = pubspecContents.replaceFirst("aqueduct: any", aqueductVersion);
    new File(directoryPath + "/pubspec.yaml").writeAsStringSync(pubspecContents);
  }

  void copyProjectFiles(Directory destinationDirectory, Directory sourceDirectory, String projectName) {
    try {
      destinationDirectory.createSync();

      new Directory(sourceDirectory.path)
          .listSync()
          .forEach((f) {
            interpretContentFile(projectName, destinationDirectory, f);
          });
    } catch (e) {
      Process.runSync("rm", ["-rf", destinationDirectory.path]);
      print("${e}");
    }
  }

  String aqueductDependencyString({String versionString: "any", String gitHost: null, String gitRef: "master", String path: null}) {
    var str = "aqueduct: ";
    if (gitHost != null) {
      str += "\n";
      str += "    git:\n";
      str += '      url: "$gitHost"\n';
      str += '      ref: "$gitRef"';
    } else if (path != null) {
      str += "\n";
      str += "    path: $path";
    } else {
      str += '"$versionString"';
    }
    return str;
  }

  String generatingPubspec(String aqueductDependencyString) {
    return 'name: aqueduct_generator\nversion: 1.0.0\nenvironment:\n  sdk: ">=1.16.0 <2.0.0"\ndependencies:\n  ' + aqueductDependencyString;
  }

  bool isSnakeCase(String string) {
    var expr = new RegExp("^[a-z][a-z0-9_]*\$");
    return expr.hasMatch(string);
  }

  String camelCaseFromSnakeCase(String string) {
    return string
        .split("_")
        .map((str) {
          var firstChar = str.substring(0, 1);
          var remainingString = str.substring(1, str.length);
          return firstChar.toUpperCase() + remainingString;
        })
        .join("");
  }
}