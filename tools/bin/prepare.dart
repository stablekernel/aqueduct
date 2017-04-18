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

  List<Transformer> transformers;
  Uri baseReferenceURL;
  String sourceBranch;
  Directory inputDirectory;
  Directory outputDirectory;
  Map<String, Map<String, List<SymbolResolution>>> symbolMap = {};
  List<String> blacklist = [
    "tools",
    "build"
  ];

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

      transformers = [new BlacklistTransformer(blacklist), new APIReferenceTransformer(symbolMap, baseReferenceURL)];

      await transformDirectory(inputDirectory, outputDirectory);

      await run("mkdocs", ["build"], directory: new Directory.fromUri(outputDirectory.uri.resolve("docs")));

      var builtDocsPath = outputDirectory.uri.resolve("docs/").resolve("site/").path;
      var finalDocsPath = outputDirectory.uri.resolve("docs/").path;
      var tempDocsPath = outputDirectory.uri.resolve("docs_tmp").path;
      await run("mv", [builtDocsPath, tempDocsPath], directory: outputDirectory);
      new Directory(finalDocsPath).deleteSync(recursive: true);
      await run("mv", [tempDocsPath, finalDocsPath], directory: outputDirectory);

    } catch (e, st) {
      print("$e $st");
      await cleanup();
      exitCode = 1;
    }
  }

  Future transformDirectory(Directory source, Directory destination) async {
    if (!destination.existsSync()) {
      destination.createSync();
    }

    var contents = source.listSync(recursive: false);
    Iterable<File> files = contents.where((fse) => fse is File);
    for (var f in files) {
      var filename = f.uri.pathSegments.last;

      List<int> contents;
      for (var transformer in transformers) {
        if (!transformer.shouldIncludeItem(filename)) {
          break;
        }

        if (!transformer.shouldTransformFile(filename)) {
          continue;
        }

        contents = contents ?? f.readAsBytesSync();
        contents = await transformer.transform(contents);
      }

      var destinationUri = destination.uri.resolve(filename);
      if (contents != null) {
        var outFile = new File.fromUri(destinationUri);
        outFile.writeAsBytesSync(contents);
      }
    }

    Iterable<Directory> subdirectories = contents.where((fse) => fse is Directory);
    for (var subdirectory in subdirectories) {
      var dirName = subdirectory.uri.pathSegments[subdirectory.uri.pathSegments.length - 2];
      var destinationDir = new Directory.fromUri(destination.uri.resolve("$dirName"));

      for (var t in transformers) {
        if (!t.shouldConsiderDirectories) {
          continue;
        }

        if (!t.shouldIncludeItem(dirName)) {
          destinationDir = null;
          break;
        }
      }

      if (destinationDir != null) {
        destinationDir.createSync(recursive: false);
        await transformDirectory(subdirectory, destinationDir);
      }
    }
  }

  Future<Map<String, Map<String, List<SymbolResolution>>>> generateSymbolMap() async {
    print("Cloning 'aqueduct' (${sourceBranch})...");
    await run(
        "git",
        ["clone", "-b", sourceBranch, "git@github.com:stablekernel/aqueduct.git"],
        directory: outputDirectory);

    print("Generating API reference...");
    var sourceDir = new Directory.fromUri(outputDirectory.uri.resolve("aqueduct"));
    await run(
      "dartdoc", [], directory: sourceDir
    );

    print("Building symbol map...");
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

  Future run(String command, List<String> args, {Directory directory}) async {
    var process = await Process.start(command, args, workingDirectory: directory.path);

    var result = await process.exitCode;
    if (result != 0) {
      throw new Exception("Command '$command' failed with exit code ${process.exitCode}");
    }
  }
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

abstract class Transformer {
  bool shouldTransformFile(String filename) => true;
  bool get shouldConsiderDirectories => false;
  bool shouldIncludeItem(String filename) => true;
  Future<List<int>> transform(List<int> inputContents) async => inputContents;
}

class BlacklistTransformer extends Transformer {
  BlacklistTransformer(this.blacklist);
  List<String> blacklist;

  @override
  bool get shouldConsiderDirectories => true;

  @override
  bool shouldIncludeItem(String filename) {
    if (filename.startsWith(".")) {
      return false;
    }

    for (var b in blacklist) {
      if (b == filename) {
        return false;
      }
    }

    return true;
  }
}

class APIReferenceTransformer extends Transformer {
  APIReferenceTransformer(this.symbolMap, this.baseReferenceURL);

  Uri baseReferenceURL;
  final RegExp regex = new RegExp("`([A-Za-z0-9_\\.\\<\\>@\\(\\)]+)`");
  Map<String, Map<String, List<SymbolResolution>>> symbolMap;

  @override
  bool shouldTransformFile(String filename) {
    return filename.endsWith(".md");
  }

  @override
  Future<List<int>> transform(List<int> inputContents) async {
    var contents = UTF8.decode(inputContents);

    var matches = regex.allMatches(contents).toList().reversed;

    matches.forEach((match) {
      var symbol = match.group(1);
      var resolution = bestGuessForSymbol(symbol);
      if (resolution != null) {
        symbol = symbol.replaceAll("<", "&lt;").replaceAll(">", "&gt;");
        var replacement = constructedReferenceURLFrom(baseReferenceURL, resolution.link.split("/"));
        contents = contents.replaceRange(match.start, match.end, "<a href=\"$replacement\">${symbol}</a>");
      } else {
//        missingSymbols.add(symbol);
      }
    });

    return UTF8.encode(contents);
  }

  SymbolResolution bestGuessForSymbol(String symbol) {
    if (symbolMap.isEmpty) {
      return null;
    }


    symbol = symbol.replaceAll("<T>", "").replaceAll("@", "").replaceAll("()", "");

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
}

Uri constructedReferenceURLFrom(Uri base, List<String> relativePathComponents) {
  var subdirectories = relativePathComponents.sublist(0, relativePathComponents.length - 1);
  Uri enclosingDir = subdirectories.fold(base, (Uri prev, elem) {
    return prev.resolve("${elem}/");
  });

  return enclosingDir.resolve(relativePathComponents.last);
}