import 'dart:io';
import 'dart:async';
import 'dart:mirrors';
import 'dart:isolate';
import 'package:args/args.dart';
import 'package:aqueduct/aqueduct.dart';

Future main(List<String> args) async {
  var parser = new ArgParser(allowTrailingOptions: false);
  parser.addOption("template", abbr: "t", defaultsTo: "default", help: "Name of the template. Defaults to default. Available options are: default");
  parser.addOption("name", abbr: "n", help: "Name of project in snake_case.");
  parser.addOption("template-directory", hide: true);
  parser.addOption("git-url", help: "Git url, will trigger generating the template from the specified git repository instead of pub.");
  parser.addOption("git-ref", defaultsTo: "master", help: "Git reference (branch or commit), will trigger generating the template from the git repository instead of pub.");
  parser.addOption("path-source", help: "Full path on filesystem, will trigger generating the template from the aqueduct source at path-source instead of pub.");
  parser.addOption("version", defaultsTo: "any", help: "Version string for aqueduct on pub for template source.");
  parser.addFlag("help", negatable: false, help: "Shows this documentation");

  var argValues = parser.parse(args);

  if (argValues["help"] == true) {
    print("${parser.usage}");
    return;
  }

  if (argValues["name"] == null || !isSnakeCase(argValues["name"])) {
    print("Invalid project name\n${parser.usage}");
    return;
  }

  var destDirectory = destinationDirectoryFromPath(argValues["name"]);
  if (destDirectory.existsSync()) {
    print("${destDirectory.path} already exists.");
    return;
  }
  destDirectory.createSync();

  print("Fetching template source...");
  var aqueductPath = await determineAqueductPath(destDirectory, argValues);
  var sourceDirectory = new Directory("${aqueductPath}/example/templates/${argValues["template"]}");

  if (argValues["template-directory"] != null) {
    sourceDirectory = new Directory("${argValues["template-directory"]}/${argValues["template"]}");
  }
  if (!sourceDirectory.existsSync()) {
    print("Error: no template named ${argValues["template"]}");
    return;
  }

  print("Copying project files...");
  await copyProjectFiles(destDirectory, sourceDirectory, argValues["name"]);

  print("Generating project files...");
  await createProjectSpecificFiles(destDirectory.path);

  print("${argValues["name"]} created at ${destDirectory.path}");
}

String determineAqueductPath(Directory projectDirectory, ArgResults argValues) {
  var temporaryPubspec = generatingPubspec(versionString: argValues["version"], gitHost: argValues["git-url"], gitRef: argValues["git-ref"], path: argValues["path-source"]);

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
    "ignite.dart",
    "ignite_test.dart"
  ];

  var lastComponent = entity.uri.pathSegments.last;
  if (lastComponent.length == 0) {
    lastComponent = entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
  }

  if (lastComponent.startsWith(".")) {
    if (lastComponent != ".gitignore") {
      return false;
    }
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

Future createProjectSpecificFiles(String directoryPath) async {
  var configSrcPath = new File(directoryPath + "/config.yaml.src");
  configSrcPath.copySync(new File(directoryPath + "/config.yaml").path);
}

void copyProjectFiles(Directory destinationDirectory, Directory sourceDirectory, String projectName) {
  try {
    destinationDirectory.createSync();

    new Directory(sourceDirectory.path)
        .listSync()
        .forEach((f) {
          interpretContentFile(projectName, destinationDirectory, f);
        });

    print("Fetching dependencies...");
    Process.runSync("pub", ["get"], workingDirectory: destinationDirectory.path);
  } catch (e) {
    Process.runSync("rm", ["-rf", destinationDirectory.path]);
    print("${e}");
  }
}

String generatingPubspec({String versionString: "any", String gitHost: null, String gitRef: "master", String path: null}) {
  var str = 'name: aqueduct_generator\nversion: 1.0.0\nenvironment:\n  sdk: ">=1.16.0 <2.0.0"\ndependencies:\n  aqueduct: ';

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

bool isSnakeCase(String string) {
  return string.toLowerCase() == string;
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