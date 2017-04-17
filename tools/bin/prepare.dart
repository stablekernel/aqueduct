import 'dart:io';
import 'dart:async';
import 'package:args/args.dart';
import 'dart:convert';

Future main(List<String> args) async {
  var options = new ArgParser(allowTrailingOptions: false)
    ..addOption("base-ref-url",
    abbr: "b", help: "Base URL of API reference", defaultsTo: "https://www.dartdocs.org/documentation/aqueduct/latest/")
    ..addOption("source-branch",
        abbr: "s",
        help: "Branch of Aqueduct to generate API reference from.",
        defaultsTo: "master")
    ..addOption("input",
        abbr: "i",
        help: "Root directory of documentation. Expects subdirectory /docs with mkdocs.yaml.",
        defaultsTo: Directory.current.path)
    ..addOption("output",
        abbr: "o",
        help: "Where to output built site. Directory created if does not exist.",
        defaultsTo: Directory.current.uri.resolve("build").path)
    ..addFlag("help", abbr: "h", help: "Shows this", negatable: false);

    var parsed = options.parse(args);
    var preparer = new Preparer(parsed["input"], parsed["output"], parsed["source-branch"], parsed["base-ref-url"]);
    await preparer.prepare();
}

class Preparer {
  Preparer(String inputDirectoryPath, String outputDirectoryPath, this.sourceBranch, String baseRefURL) {
    inputDirectory = new Directory(inputDirectoryPath);
    outputDirectory = new Directory(outputDirectoryPath);
    baseReferenceURL = Uri.parse(baseRefURL);
  }

  Uri baseReferenceURL;
  String sourceBranch;
  Directory inputDirectory;
  Directory outputDirectory;
  Map<String, Map<String, List<SymbolResolution>>> symbolMap = {};
  Directory get documentDirectory =>
    new Directory.fromUri(inputDirectory.uri.resolve("docs/").resolve("docs/"));

  List<File> get documents =>
    documentDirectory
        .listSync(recursive: true)
        .where((fse) => fse.path.endsWith(".md"))
        .where((fse) => fse is File)
        .toList();

  Future cleanup() async {
    await outputDirectory.delete(recursive: true);
  }

  Future prepare() async {
    try {
      if (!outputDirectory.existsSync()) {
        await outputDirectory.create(recursive: true);
      } else {
        await outputDirectory.delete(recursive: true);
        await outputDirectory.create(recursive: true);
      }

      symbolMap = await generateSymbolMap();

      await buildGuides();

    } catch (e, st) {
      print("$e $st");
      await cleanup();
      exitCode = 1;
    }
  }

  SymbolResolution bestGuessForSymbol(String symbol) {
    if (symbolMap.isEmpty) {
      return null;
    }

    var possible = symbolMap["qualified"][symbol];
    if (possible == null) {
      possible = symbolMap["name"][symbol];
    }

    if (possible == null) {
      return null;
    }

    if (possible.length == 1) {
      return possible.first;
    }

    return possible.firstWhere((r) => r.type == "class",
        orElse: () => possible.first);
  }

  Future<Map<String, Map<String, List<SymbolResolution>>>> generateSymbolMap() async {
    await run(
        "git",
        ["clone", "-b", sourceBranch, "git@github.com:stablekernel/aqueduct.git"],
        directory: outputDirectory);

    var sourceDir = new Directory.fromUri(outputDirectory.uri.resolve("aqueduct"));
    await run(
      "dartdoc", [], directory: sourceDir
    );

    var indexFile = new File.fromUri(sourceDir.uri.resolve("doc/").resolve("api/").resolve("index.json"));
    List<Map<String, dynamic>> indexJSON = JSON.decode(await indexFile.readAsString());
    var libraries = indexJSON
        .where((m) => m["type"] == "library")
        .map((lib) => lib["qualifiedName"])
        .toList();

    List<SymbolResolution> resolutions = indexJSON
        .where((m) => m["type"] != "library")
        .map((obj) => new SymbolResolution.fromMap(obj))
        .toList();

    var qualifiedMap = <String, List<SymbolResolution>>{};
    var nameMap = <String, List<SymbolResolution>>{};
    resolutions.forEach((resolution) {
      if (!nameMap.containsKey(resolution.name)) {
        nameMap[resolution.name] = [resolution];
      } else {
        nameMap[resolution.name].add(resolution);
      }

      var qualifiedKey = libraries
          .fold(resolution.qualifiedName, (String p, e) {
            return p.replaceFirst("${e}.", "");
          });
      if (!qualifiedMap.containsKey(qualifiedKey)) {
        qualifiedMap[qualifiedKey] = [resolution];
      } else {
        qualifiedMap[qualifiedKey].add(resolution);
      }
    });

    await sourceDir.delete(recursive: true);

    return {
      "qualified": qualifiedMap,
      "name": nameMap
    };
  }

  Uri constructedReferenceURLFrom(Uri base, List<String> relativePathComponents) {
    var subdirectories = relativePathComponents.sublist(0, relativePathComponents.length - 1);
    Uri enclosingDir = subdirectories.fold(base, (Uri prev, elem) {
      return prev.resolve("${elem}/");
    });


    return enclosingDir.resolve(relativePathComponents.last);
  }

  Future buildGuides() async {
    var intermediateDirectory = new Directory.fromUri(outputDirectory.uri.resolve("intermediate/"));
    await intermediateDirectory.create(recursive: true);

    List<String> missingSymbols = [];
    var files = documents;
    var regex = new RegExp("`([A-Za-z0-9_\\.]+)`");

    var fileOps = files
      .map((file) async {
        var contents = await file.readAsString();
        var matches = regex.allMatches(contents).toList().reversed;

        matches.forEach((match) {
          var symbol = match.group(1);
          var resolution = bestGuessForSymbol(symbol);
          if (resolution != null) {
            var replacement = constructedReferenceURLFrom(baseReferenceURL, resolution.link.split("/"));
            contents = contents.replaceRange(match.start, match.end, "<a href=\"$replacement\">${symbol}</a>");
          } else {
            missingSymbols.add(symbol);
          }
        });

        var intermediateUri = constructedReferenceURLFrom(intermediateDirectory.uri, relativePathComponents(documentDirectory.uri, file.uri));

        var intermediateFile = new File.fromUri(intermediateUri);
        if (!intermediateFile.parent.existsSync()) {
          await intermediateFile.parent.create(recursive: true);
        }

        await intermediateFile.writeAsString(contents);
      });

    await Future.wait(fileOps);

    print("Unknown symbols: ");
    print("${missingSymbols.join(", ")}");
  }

  List<String> relativePathComponents(Uri base, Uri path) {
    var baseComponents = base.pathSegments;
    var pathComponents = path.pathSegments;
    var componentDiff = pathComponents.length - baseComponents.length + 1;

    return pathComponents.sublist(pathComponents.length - componentDiff);
  }


  Future run(String command, List<String> args, {Directory directory}) async {
    var process = await Process.start(command, args, workingDirectory: directory.path);

    var result = await process.exitCode;
    if (result != 0) {
      throw new Exception("Command '$command' failed with exit code ${process.exitCode}");
    }
  }
}

class SymbolReference {
  SymbolReference(this.filename, this.startPosition, this.endPosition, this.symbolName);

  String filename;
  int startPosition;
  int endPosition;
  String symbolName;

  String toString() => "$filename:$startPosition:$endPosition $symbolName";
}

class SymbolResolution {
  SymbolResolution.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    qualifiedName = map["qualifiedName"];
    link = map["href"];
    type = map["type"];
  }

  String name;
  String qualifiedName;
  String type;
  String link;

  String toString() => "$name: $qualifiedName $link $type";
}