import 'dart:io';
import 'dart:async';

Future main(List<String> args) async {
  var useBranch = "master";
  if (args.length == 2) {
    useBranch = args.last;
  }

  Directory destDirectory = destinationDirectoryFromPath(args.first);
  if (destDirectory.existsSync()) {
    throw new Exception("Error: file already exists at path ${destDirectory.path}.");
  }

  var sourceDirectory = new Directory("${destDirectory.path}_temp");
  await cloneTemplateToDirectory(sourceDirectory, branch: useBranch);

  var projectName = projectNameFromPath(destDirectory.path);
  await copyProjectFiles(destDirectory, sourceDirectory, projectName);

  await createProjectSpecificFiles(destDirectory.path);

  print("${projectName} exists at ${destDirectory.path}");
}

String readmeContents() {
  return "###Setup\nEnsure that database access has been setup via the instructions here: https://github.com/stablekernel/wildfire/blob/master/README.md";
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
    "README.md",
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

void copyDirectory(String projectName, Directory destinationParentDirectory,
    Directory sourceDirectory) {
  var sourceDirectoryName = sourceDirectory.uri.pathSegments[sourceDirectory.uri
      .pathSegments.length - 2];
  var destDir = new Directory(
      destinationParentDirectory.path + "/" + sourceDirectoryName);
  destDir.createSync();
  sourceDirectory.listSync().forEach((f) {
    interpretContentFile(projectName, destDir, f);
  });
}

void copyFile(String projectName, Directory destinationDirectory,
    File sourceFile) {
  var path = destinationDirectory.path + "/" +
      fileNameForFile(projectName, sourceFile);
  var contents = sourceFile.readAsStringSync();

  var lowercase = lowercaseProjectName(projectName);
  var uppercase = uppercaseProjectName(projectName);
  contents = contents.replaceAll("wildfire", "$lowercase");
  contents = contents.replaceAll("Wildfire", "$uppercase");


  var outputFile = new File(path);
  outputFile.createSync();
  outputFile.writeAsStringSync(contents);
}

String lowercaseProjectName(String projectName) {
  return projectName.toLowerCase();
}

String uppercaseProjectName(String projectName) {
  return projectName.replaceRange(
      0, 1, projectName.substring(0, 1).toUpperCase());
}

String fileNameForFile(String projectName, File sourceFile) {
  var lowercase = lowercaseProjectName(projectName);
  var fileName = sourceFile.uri.pathSegments.last;
  fileName = fileName.replaceFirst("S___LOWER_APPLICATION_NAME___", lowercase);

  if (fileName == "wildfire.iml") {
    fileName = "$lowercase.iml";
  } else if (fileName == "wildfire.dart") {
    fileName = "$lowercase.dart";
  }

  return fileName;
}

void cloneTemplateToDirectory(Directory dir, {String branch: "master"}) {
  print("Fetching template source from git...");
  Process.runSync("git", [
    "clone", "https://github.com/stablekernel/wildfire.git", dir.path
  ]);

  if (branch != "master") {
    Process.runSync("git", ["checkout", branch], workingDirectory: dir.path);
  }
}

Directory destinationDirectoryFromPath(String pathString) {
  if (pathString.startsWith("/")) {
    return new Directory(pathString);
  } else {
    var currentDirPath = Directory.current.uri.toFilePath();
    if (!currentDirPath.endsWith("/")) {
      currentDirPath += "/";
    }
    currentDirPath += pathString;
    return new Directory(currentDirPath);
  }
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
  var readmePath = new File(directoryPath + "/README.md");
  var readmeSink = readmePath.openWrite();
  readmeSink.write(readmeContents());
  await readmeSink.close();

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
    var result = Process.runSync("pub", ["get"], workingDirectory: destinationDirectory.path);
  } catch (e) {
    Process.runSync("rm", ["-rf", destinationDirectory.path]);
    print("${e}");
  } finally {
    Process.runSync("rm", ["-rf", sourceDirectory.path]);
  }
}