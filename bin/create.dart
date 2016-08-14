import 'dart:io';
import 'dart:async';
import 'dart:mirrors';
import 'dart:isolate';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var packageURI = await Isolate.resolvePackageUri(new Uri(scheme: "package", path: "aqueduct/aqueduct.dart"));
  var parser = new ArgParser(allowTrailingOptions: false);
  parser.addOption("template", abbr: "t", defaultsTo: "default", help: "Name of the template. Defaults to default. Available options are: default");
  parser.addOption("name", abbr: "n", help: "Name of project in snake_case.");
  parser.addFlag("local", abbr: "l", defaultsTo: false, hide: true);

  var argValues = parser.parse(args);

  if (!isSnakeCase(argValues["name"])) {
    print("Invalid project name\n${parser.usage}");
    return;
  }

  Directory destDirectory = destinationDirectoryFromPath(argValues["name"]);
  if (destDirectory.existsSync()) {
    print("Error: file already exists at path ${destDirectory.path}.");
    return;
  }

  var sourceDirectory = new Directory("${packageURI.path}/example/templates/${argValues["template"]}");
  if (!sourceDirectory.existsSync()) {
    print("Error: no template named ${argValues["template"]}");
    return;
  }

  await copyProjectFiles(destDirectory, sourceDirectory, argValues["name"]);

  await createProjectSpecificFiles(destDirectory.path);

  print("${argValues["name"]} created at ${destDirectory.path}");
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
  // Put config.yaml in, but then also put it in the gitignore.
  var configSrcPath = new File(directoryPath + "/config.yaml.src");
  configSrcPath.copySync(new File(directoryPath + "/config.yaml").path);

  var gitIgnoreFile = new File(directoryPath + "/.gitignore");
  var contents = gitIgnoreFile.readAsStringSync();
  contents = contents.replaceFirst("pubspec.lock", "");

  gitIgnoreFile.writeAsStringSync(contents, mode: FileMode.WRITE);
}

void copyProjectFiles(Directory destinationDirectory, Directory sourceDirectory, String projectName) {
  print("Creating project '$projectName'...");
  try {
    print("Supplying project values...");
    destinationDirectory.createSync();

    new Directory(sourceDirectory.path).listSync().forEach((f) {
      interpretContentFile(projectName, destinationDirectory, f);
    });

    print("Fetching dependencies...");
    Process.runSync("pub", ["get"], workingDirectory: destinationDirectory.path);
  } catch (e) {
    Process.runSync("rm", ["-rf", destinationDirectory.path]);
    print("${e}");
  }
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