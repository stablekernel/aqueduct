import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:http/http.dart' as http;
import 'package:safe_config/safe_config.dart';
import 'package:args/args.dart';

Future main(List<String> args) async {
  var parser = new ArgParser()
    ..addOption("config", abbr: "c", defaultsTo: "release.yaml");
  var runner = new Runner(parser.parse(args));

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
    configuration = new ReleaseConfig(options["config"]);
  }

  ArgResults options;
  ReleaseConfig configuration;
  List<Function> _cleanup = [];

  Future cleanup() async {
    return Future.forEach(_cleanup, (f) => f());
  }

  Future<int> run() async {
    // Ensure we have all the appropriate command line utilties as a pre-check
    // - git

    // Clone master into a temp directory
    var master = await directoryWithBranch("master");
    var previousVersion = await latestVersion();
    var upcomingVersion = await versionFromDirectory(master);
    if (upcomingVersion == previousVersion) {
      throw "Release failed. Version $upcomingVersion already exists.";
    }

    print("Preparing to release $upcomingVersion (from $previousVersion)...");
    var changeset = await changesFromDirectory(master, upcomingVersion);

    // Ensure changelog has entries for that version by parsing markdown
    // Use GitHub API to tag master as release with above info

    // Clone docs/source into another directory.
    // Run its publish tool

    return 0;
  }

  Future<Directory> directoryWithBranch(String branchName) async {
    var dir = await Directory.current.createTemp(branchName);
    _cleanup.add(() => dir.delete(recursive: true));

    print("Cloning '$branchName' into ${dir.path}...");
    var result = await Process.run(
        "git",
        ["clone", "-b", branchName, "git@github.com:stablekernel/aqueduct.git"],
        workingDirectory: dir.path);

    if (result.exitCode != 0) {
      throw "directoryWithBranch ($branchName) failed with exit code ${result.exitCode}. Reason: ${result.stdout} ${result.stderr}";
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

    String tag = JSON.decode(response.body)["tag_name"];
    if (tag == null) {
      throw "latestVersion failed. Reason: no tag found";
    }

    return tag.trim();
  }

  Future<String> versionFromDirectory(Directory directory) async {
    var pubspecFile = new File.fromUri(directory.uri.resolve("pubspec.yaml"));
    var yaml = loadYaml(await pubspecFile.readAsString());

    return "v" + (yaml["version"] as String).trim();
  }

  Future<String> changesFromDirectory(Directory directory, String prefixedVersion) async {
    // Strip "v"
    var version = prefixedVersion.substring(1);
    assert(version.split(".").length == 3);

    var regex = new RegExp(r"^([0-9]+\.[0-9]+\.[0-9]+)");

    var changelogFile = new File.fromUri(directory.uri.resolve("CHANGELOG.md"));
    var changelogContents = await changelogFile.readAsString();
    var latestChangelogEntry = changelogContents.split("##").map((s) => s.trim()).first;
    var latestChangelogVersion = regex.firstMatch(latestChangelogEntry).group(1);

    if (latestChangelogVersion != version) {
      throw "Release failed. No entry in CHANGELOG.md for $version.";
    }

    return latestChangelogEntry.substring(latestChangelogVersion.length);
  }
}



class ReleaseConfig extends ConfigurationItem {
  ReleaseConfig(String filename) : super.fromFile(filename);

  String githubToken;
}