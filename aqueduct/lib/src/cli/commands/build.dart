import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/running_process.dart';
import 'package:aqueduct/src/cli/scripts/get_channel_type.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:runtime/runtime.dart';

class CLIBuild extends CLICommand with CLIProject {
/*  @Option("timeout",
    help: "Number of seconds to wait to ensure startup succeeded.",
    defaultsTo: "45")
  int get startupTimeout => decode("timeout");

  @Option("ssl-key-path",
    help:
    "The path to an SSL private key file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.")
  String get keyPath => decode("ssl-key-path");

  @Option("ssl-certificate-path",
    help:
    "The path to an SSL certicate file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.")
  String get certificatePath => decode("ssl-certificate-path");

  @Flag("ipv6-only",
    help: "Limits listening to IPv6 connections only.",
    negatable: false,
    defaultsTo: false)
  bool get ipv6Only => decode("ipv6-only");

  @Option("port",
    abbr: "p",
    help: "The port number to listen for HTTP requests on.",
    defaultsTo: "8888")
  int get port => decode("port");

  @Option("isolates", abbr: "n", help: "Number of isolates processing requests")
  int get numberOfIsolates {
    int isolateCount = decode("isolates");
    if (isolateCount == null) {
      final count = Platform.numberOfProcessors ~/ 2;
      return count > 0 ? count : 1;
    }
    return isolateCount;
  }

  @Option("address",
    abbr: "a",
    help:
    "The address to listen on. See HttpServer.bind for more details; this value is used as the String passed to InternetAddress.lookup."
      " Using the default will listen on any address.")
  String get address => decode("address");

  @Option("config-path",
    abbr: "c",
    help:
    "The path to a configuration file. This File is available in the ApplicationOptions"
      "for a ApplicationChannel to use to read application-specific configuration values. Relative paths are relative to [directory].",
    defaultsTo: "config.yaml")
  File get configurationFile => File(decode("config-path")).absolute;
*/

  // Add retain build product as a flag

  @override
  Future<int> handle() async {
    final root = Directory.current.uri;
    final libraryUri = root.resolve("lib/").resolve("$libraryName.dart");
    final ctx = BuildContext(
      libraryUri,
      root.resolve("build/"),
      root.resolve("$libraryName.aot"),
      f.readAsStringSync(), // need to generate this file
      forTests: false);
    final bm = BuildManager(ctx);
    await bm.build();
  }

  @override
  Future cleanup() async {

  }


  @override
  String get name {
    return "build";
  }

  @override
  String get description {
    return "Creates an executable of an Aqueduct application.";
  }
}