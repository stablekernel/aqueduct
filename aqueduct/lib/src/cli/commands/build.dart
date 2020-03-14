import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:runtime/runtime.dart';

class CLIBuild extends CLICommand with CLIProject {
  @Flag("retain-build-artifacts",
      help:
          "Whether or not the 'build' directory should be left intact after the application is compiled.",
      defaultsTo: false)
  bool get retainBuildArtifacts => decode("retain-build-artifacts");

  @Option("build-directory",
      help:
          "The directory to store build artifacts during compilation. By default, this directory is deleted when this command completes. See 'retain-build-artifacts' flag.",
      defaultsTo: "build")
  Directory get buildDirectory => Directory(decode("build-directory")).absolute;

  @override
  Future<int> handle() async {
    final root = projectDirectory.uri;
    final libraryUri = root.resolve("lib/").resolve("$libraryName.dart");
    final ctx = BuildContext(
        libraryUri,
        buildDirectory.uri,
        root.resolve("$packageName.aot"),
        getScriptSource(await getChannelName()),
        forTests: false);

    final bm = BuildManager(ctx);
    await bm.build();

    return 0;
  }

  @override
  Future cleanup() async {
    if (!retainBuildArtifacts) {
      buildDirectory.deleteSync(recursive: true);
    }
  }

  @override
  String get name {
    return "build";
  }

  @override
  String get description {
    return "Creates an executable of an Aqueduct application.";
  }

  String getScriptSource(String channelName) {
    return """
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/cli/starter.dart';
import 'package:$packageName/$libraryName.dart';

Future main(List<String> args, dynamic sendPort) async {
    final app = new Application<$channelName>();
    
    // We need to get config from cli args...
    var config = new ApplicationOptions();

    app.options = config;
    
    await app.start(numberOfInstances: 1);
}
""";
  }
}
