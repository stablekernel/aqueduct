import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:safe_config/safe_config.dart';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = ArgParser()
    ..addFlag("dry-run")
    ..addFlag("docs-only")
    ..addOption("name")
    ..addOption("config", abbr: "c", defaultsTo: "release.yaml");
  var runner = Runner(parser.parse(args));

  try {
    exitCode = await runner.run();
  } catch (e, st) {
    print("Release failed!");
    print("$e");
    print("$st");
    exitCode = -1;
  } finally {
    await runner.cleanup();
  }
}

class Runner {
  Runner(this.options) {
    configuration = ReleaseConfig(options["config"] as String);
  }

  ArgResults options;
  ReleaseConfig configuration;
  List<Function> _cleanup = [];
  bool get isDryRun => options["dry-run"] as bool;
  bool get docsOnly => options["docs-only"] as bool;
  String get name => options["name"] as String;
  Uri baseReferenceURL = Uri.parse("https://www.dartdocs.org/documentation/aqueduct/latest/");

  Future cleanup() async {
    return Future.forEach(_cleanup, (f) => f());
  }

  Future<int> run() async {
    // Ensure we have all the appropriate command line utilities as a pre-check
    // - git
    // - pub
    // - mkdocs

    if (name == null && !(isDryRun || docsOnly)) {
      throw "--name is required.";
    }

    print("Preparing release: '$name'... ${isDryRun ? "(dry-run)":""} ${docsOnly ? "(docs-only)":""}");

    var master = await directoryWithBranch("master");
    String upcomingVersion;
    String changeset;
    if (!docsOnly) {
      var previousVersion = await latestVersion();
      upcomingVersion = await versionFromDirectory(master);
      if (upcomingVersion == previousVersion) {
        throw "Release failed. Version $upcomingVersion already exists.";
      }

      print("Preparing to release $upcomingVersion (from $previousVersion)...");
      changeset = await changesFromDirectory(master, upcomingVersion);
    }

    // Clone docs/source into another directory.
    var docsSource = await directoryWithBranch("docs/source");
    await publishDocs(docsSource, master);

    if (!docsOnly) {
      await postGithubRelease(upcomingVersion, name, changeset);
      await publish(master);
    }

    return 0;
  }

  Future publishDocs(Directory docSource, Directory code) async {
    var symbolMap = await generateSymbolMap(code);
    var blacklist = [
      "tools",
      "build"
    ];
    var transformers = [
      BlacklistTransformer(blacklist),
      APIReferenceTransformer(symbolMap, baseReferenceURL)
    ];

    var docsLive = await directoryWithBranch("gh-pages");
    print("Cleaning ${docsLive.path}...");
    docsLive
      .listSync()
      .where((fse) {
        if (fse is Directory) {
          var lastPathComponent = fse.uri.pathSegments[fse.uri.pathSegments.length - 2];
          return lastPathComponent != ".git";
        } else if (fse is File) {
          return fse.uri.pathSegments.last != ".nojekyll";
        }
        return false;
      })
      .forEach((fse) {
        fse.deleteSync(recursive: true);
      });

    print("Transforming docs from ${docSource.path} into ${docsLive.path}...");
    await transformDirectory(transformers, docSource, docsLive);

    print("Building /source to /docs site with mkdoc...");
    var process = await Process.start(
        "mkdocs", ["build", "-d", docsLive.uri.resolve("docs").path, "-s"],
        workingDirectory: docsLive.uri.resolve("source").path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    var exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "mkdocs failed with exit code $exitCode.";
    }

    var sourceDirectoryInLive = Directory.fromUri(docsLive.uri.resolve("source"));
    sourceDirectoryInLive.deleteSync(recursive: true);
    process = await Process.start("git", ["add", "."], workingDirectory: docsLive.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "git add in ${docsLive.path} failed with exit code $exitCode.";
    }

    process = await Process.start("git", ["commit", "-m", "commit by release tool"], workingDirectory: docsLive.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);
    exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "git commit in ${docsLive.path} failed with exit code $exitCode.";
    }

    // Push gh-pages to remote
    if (!isDryRun) {
      print("Pushing gh-pages to remote...");
      var process = await Process.start("git", ["push"], workingDirectory: docsLive.path);
      // ignore: unawaited_futures
      stderr.addStream(process.stderr);
      // ignore: unawaited_futures
      stdout.addStream(process.stdout);
      var exitCode = await process.exitCode;
      if (exitCode != 0) {
        throw "git push to ${docsLive.path} failed with exit code $exitCode.";
      }
    }
  }

  Future<Directory> directoryWithBranch(String branchName) async {
    var dir = await Directory.current.createTemp(branchName.replaceAll("/", "_"));
    _cleanup.add(() => dir.delete(recursive: true));

    print("Cloning '$branchName' into ${dir.path}...");
    var process = await Process.start(
        "git",
        ["clone", "-b", branchName, "git@github.com:stablekernel/aqueduct.git", dir.path]);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    // stdout.addStream(process.stdout);

    var exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "directoryWithBranch ($branchName) failed with exit code $exitCode.";
    }

    return dir;
  }

  Future<String> latestVersion() async {
    print("Getting latest version...");
    var response = await http.get(
        "https://api.github.com/repos/stablekernel/aqueduct/releases/latest",
        headers: {"Authorization": "Bearer ${configuration.githubToken}"});

    if (response.statusCode != 200) {
      throw "latestVersion failed with status code ${response.statusCode}. Reason: ${response.body}";
    }

    final tag = json.decode(response.body)["tag_name"] as String;
    if (tag == null) {
      throw "latestVersion failed. Reason: no tag found";
    }

    return tag.trim();
  }

  Future<String> versionFromDirectory(Directory directory) async {
    var pubspecFile = File.fromUri(directory.uri.resolve("pubspec.yaml"));
    var yaml = loadYaml(await pubspecFile.readAsString());

    return "v${(yaml["version"] as String).trim()}";
  }

  Future<String> changesFromDirectory(Directory directory, String prefixedVersion) async {
    // Strip "v"
    var version = prefixedVersion.substring(1);
    assert(version.split(".").length == 3);

    var regex = RegExp(r"^## ([0-9]+\.[0-9]+\.[0-9]+)", multiLine: true);

    var changelogFile = File.fromUri(directory.uri.resolve("CHANGELOG.md"));
    var changelogContents = await changelogFile.readAsString();
    var versionContentsList = regex.allMatches(changelogContents).toList();
    var latestChangelogVersion = versionContentsList.firstWhere((m) => m.group(1) == version, orElse: () {
      throw "Release failed. No entry in CHANGELOG.md for $version.";
    });

    var changeset = changelogContents.substring(
        latestChangelogVersion.end,
        versionContentsList[versionContentsList.indexOf(latestChangelogVersion) + 1].start).trim();

    print("Changeset for $prefixedVersion:");
    print("$changeset");

    return changeset;
  }

  Future postGithubRelease(String version, String name, String description) async {
    var body = json.encode({
      "tag_name": version,
      "name": name,
      "body": description
    });

    print("Tagging GitHub release $version");
    print("- $name");

    if (!isDryRun) {
      var response = await http.post("https://api.github.com/repos/stablekernel/aqueduct/releases",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer ${configuration.githubToken}"
        }, body: body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw "GitHub release tag failed with status code ${response.statusCode}. Reason: ${response.body}.";
      }
    }
  }

  Future publish(Directory master) async {
    print("Formatting code...");
    final fmt = await Process.run("dartfmt", ["-w", "lib/", "bin/"]);
    if (fmt.exitCode != 0) {
      print("WARNING: Failed to run 'dartfmt -w lib/ bin/");
    }

    print("Publishing to pub...");
    var args = ["publish"];
    if (isDryRun) {
      args.add("--dry-run");
    } else {
      args.add("-f");
    }

    var process = await Process.start("pub", args, workingDirectory: master.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);

    var exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "Publish failed with exit code: $exitCode.";
    }
  }

  Future<Map<String, Map<String, List<SymbolResolution>>>> generateSymbolMap(Directory codeBranchDir) async {
    print("Generating API reference...");
    var process = await Process.start("dartdoc", [], workingDirectory: codeBranchDir.path);
    // ignore: unawaited_futures
    stderr.addStream(process.stderr);
    // ignore: unawaited_futures
    stdout.addStream(process.stdout);

    var exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw "Release failed. Generating API reference failed with exit code: $exitCode.";
    }

    print("Building symbol map...");
    var indexFile = File.fromUri(codeBranchDir.uri.resolve("doc/").resolve("api/").resolve("index.json"));
    final indexJSON = json.decode(await indexFile.readAsString()) as List<Map<String, dynamic>>;
    var libraries = indexJSON
        .where((m) => m["type"] == "library")
        .map((lib) => lib["qualifiedName"])
        .toList();

    List<SymbolResolution> resolutions = indexJSON
        .where((m) => m["type"] != "library")
        .map((obj) => SymbolResolution.fromMap(obj.cast()))
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
        return p.replaceFirst("$e.", "");
      });
      if (!qualifiedMap.containsKey(qualifiedKey)) {
        qualifiedMap[qualifiedKey] = [resolution];
      } else {
        qualifiedMap[qualifiedKey].add(resolution);
      }
    });

    return {
      "qualified": qualifiedMap,
      "name": nameMap
    };
  }

  Future transformDirectory(List<Transformer> transformers, Directory source, Directory destination) async {
    var contents = source.listSync(recursive: false);
    var files = contents
        .whereType<File>();
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
        var outFile = File.fromUri(destinationUri);
        outFile.writeAsBytesSync(contents);
      }
    }

    Iterable<Directory> subdirectories = contents
        .whereType<Directory>();
    for (var subdirectory in subdirectories) {
      var dirName = subdirectory.uri.pathSegments[subdirectory.uri.pathSegments.length - 2];
      var destinationDir = Directory.fromUri(destination.uri.resolve("$dirName"));

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
        await transformDirectory(transformers, subdirectory, destinationDir);
      }
    }
  }
}

class ReleaseConfig extends Configuration {
  ReleaseConfig(String filename) : super.fromFile(File(filename));

  String githubToken;
}

//////

class SymbolResolution {
  SymbolResolution.fromMap(Map<String, String> map) {
    name = map["name"];
    qualifiedName = map["qualifiedName"];
    link = map["href"];
    type = map["type"];
  }

  String name;
  String qualifiedName;
  String type;
  String link;

  @override
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
  final RegExp regex = RegExp("`([A-Za-z0-9_\\.\\<\\>@\\(\\)]+)`");
  Map<String, Map<String, List<SymbolResolution>>> symbolMap;

  @override
  bool shouldTransformFile(String filename) {
    return filename.endsWith(".md");
  }

  @override
  Future<List<int>> transform(List<int> inputContents) async {
    var contents = utf8.decode(inputContents);

    var matches = regex.allMatches(contents).toList().reversed;

    matches.forEach((match) {
      var symbol = match.group(1);
      var resolution = bestGuessForSymbol(symbol);
      if (resolution != null) {
        symbol = symbol.replaceAll("<", "&lt;").replaceAll(">", "&gt;");
        var replacement = constructedReferenceURLFrom(baseReferenceURL, resolution.link.split("/"));
        contents = contents.replaceRange(match.start, match.end, "<a href=\"$replacement\">$symbol</a>");
      } else {
//        missingSymbols.add(symbol);
      }
    });

    return utf8.encode(contents);
  }

  SymbolResolution bestGuessForSymbol(String inputSymbol) {
    if (symbolMap.isEmpty) {
      return null;
    }

    final symbol = inputSymbol.replaceAll("<T>", "").replaceAll("@", "").replaceAll("()", "");

    var possible = symbolMap["qualified"][symbol];
    possible ??= symbolMap["name"][symbol];

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
    return prev.resolve("$elem/");
  });

  return enclosingDir.resolve(relativePathComponents.last);
}