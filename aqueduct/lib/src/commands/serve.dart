import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:aqueduct/src/commands/running_process.dart';
import 'package:aqueduct/src/commands/scripts/get_channel_type.dart';
import 'package:args/args.dart';
import 'package:isolate_executor/isolate_executor.dart';
import 'package:path/path.dart' as path_lib;

import 'base.dart';
import 'dart:developer';

class CLIServer extends CLICommand with CLIProject {
  CLIServer() {
    options
      ..addOption("channel",
          abbr: "s",
          help: "The name of the ApplicationChannel subclass to be instantiated to serve requests. "
              "By default, this subclass is determined by reflecting on the application library in the [directory] being served.")
      ..addOption("port", abbr: "p", help: "The port number to listen for HTTP requests on.", defaultsTo: "8888")
      ..addOption("address",
          abbr: "a",
          help:
              "The address to listen on. See HttpServer.bind for more details; this value is used as the String passed to InternetAddress.lookup."
              " Using the default will listen on any address.")
      ..addOption("config-path",
          abbr: "c",
          help: "The path to a configuration file. This File is available in the ApplicationOptions"
              "for a ApplicationChannel to use to read application-specific configuration values. Relative paths are relative to [directory].",
          defaultsTo: "config.yaml")
      ..addOption("timeout", help: "Number of seconds to wait to ensure startup succeeded.", defaultsTo: "20")
      ..addOption("isolates", abbr: "n", help: "Number of isolates processing requests", defaultsTo: "3")
      ..addOption("ssl-key-path",
          help:
              "The path to an SSL private key file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.")
      ..addOption("ssl-certificate-path",
          help:
              "The path to an SSL certicate file. If provided along with --ssl-certificate-path, the application will be HTTPS-enabled.")
      ..addFlag("ipv6-only", help: "Limits listening to IPv6 connections only.", negatable: false, defaultsTo: false)
      ..addFlag("observe", help: "Enables Dart Observatory", defaultsTo: false);
  }

  String derivedChannelType;

  ArgResults get command => values.command;

  int get startupTimeout => int.parse(values["timeout"]);

  String get keyPath => values["ssl-key-path"];

  String get certificatePath => values["ssl-certificate-path"];

  bool get shouldRunObservatory => values["observe"];

  bool get ipv6Only => values["ipv6-only"];

  int get port => int.parse(values["port"]);

  int get numberOfIsolates => int.parse(values["isolates"]);

  String get address => values["address"];

  String get channelType => values["channel"] ?? derivedChannelType;

  File get configurationFile => new File(values["config-path"]).absolute;

  ReceivePort messagePort;
  ReceivePort errorPort;
  Completer<int> exitCode = new Completer<int>();

  @override
  StoppableProcess runningProcess;

  @override
  Future<int> handle() async {
    await prepare();

    try {
      runningProcess = await start();
    } catch (e, st) {
      displayError("Application failed to start.");
      exitCode.completeError(e, st);
    }

    return exitCode.future;
  }

  @override
  Future cleanup() async {
    messagePort?.close();
    errorPort?.close();
  }

  /////

  Future<StoppableProcess> start() async {
    var replacements = {
      "PACKAGE_NAME": packageName,
      "LIBRARY_NAME": libraryName,
      "CHANNEL_TYPE": channelType,
      "PORT": port,
      "ADDRESS": address,
      "IPV6_ONLY": ipv6Only,
      "NUMBER_OF_ISOLATES": numberOfIsolates,
      "CONFIGURATION_FILE_PATH": configurationFile.path,
      "SSL_KEY_PATH": keyPath,
      "SSL_CERTIFICATE_PATH": certificatePath
    };

    displayInfo("Starting application '$packageName/$libraryName'");
    displayProgress("Channel: $channelType");
    displayProgress("Config: ${configurationFile?.path}");
    displayProgress("Port: $port");

    errorPort = new ReceivePort();
    messagePort = new ReceivePort();

    final generatedStartScript = createScriptSource(replacements);
    final dataUri = Uri.parse("data:application/dart;charset=utf-8,${Uri.encodeComponent(generatedStartScript)}");
    final startupCompleter = new Completer<SendPort>();

    final isolate = await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        packageConfig: fileInProjectDirectory(".packages").uri,
        paused: true);

    errorPort.listen((msg) {
      if (msg is List<String>) {
        startupCompleter.completeError(msg.first, new StackTrace.fromString(msg.last));
      }
    });

    messagePort.listen((msg) {
      switch (msg["status"]) {
        case "ok":
          {
            startupCompleter.complete(msg["port"]);
          }
          break;
        case "stopped":
          {
            exitCode.complete(0);
          }
      }
    });

    isolate.resume(isolate.pauseCapability);

    if (shouldRunObservatory) {
      final observatory = await Service.controlWebServer(enable: true);
      if (await supportsLaunchObservatory()) {
        await launchObservatory(observatory.serverUri.toString());
      }
    }

    final sendPort = await startupCompleter.future.timeout(new Duration(seconds: startupTimeout));
    final process = new StoppableProcess((reason) async {
      displayInfo("Stopping application.");
      displayProgress("Reason: $reason");
      sendPort.send({"command": "stop"});
    });

    return process;
  }

  Future<String> deriveApplicationLibraryDetails() async {
    final name = await IsolateExecutor.executeWithType(GetChannelExecutable,
        packageConfigURI: packageConfigUri, imports: GetChannelExecutable.importsForPackage(libraryName), logHandler: displayProgress);
    if (name == null) {
      throw new CLIException("No ApplicationChannel subclass found in $packageName/$libraryName");
    }

    return name;
  }

  Future prepare() async {
    if (keyPath != null && certificatePath == null) {
      throw new CLIException("Configuration error: --ssl-key-path was specified, but --ssl-certificate-path was not.");
    }
    if (keyPath == null && certificatePath != null) {
      throw new CLIException("Configuration error: --ssl-certificate-path was specified, but --ssl-key-path was not.");
    }

    displayInfo("Preparing...");
    derivedChannelType = await deriveApplicationLibraryDetails();
  }

  String createScriptSource(Map<String, dynamic> values) {
    var addressString = "..address = \"___ADDRESS___\"";
    if (values["ADDRESS"] == null) {
      addressString = "";
    }
    var configString = "..configurationFilePath = r\"___CONFIGURATION_FILE_PATH___\"";
    if (values["CONFIGURATION_FILE_PATH"] == null) {
      configString = "";
    }
    var certificateString = "..certificateFilePath = r\"___SSL_CERTIFICATE_PATH___\"";
    if (values["SSL_CERTIFICATE_PATH"] == null) {
      certificateString = "";
    }
    var keyString = "..privateKeyFilePath = r\"___SSL_KEY_PATH___\"";
    if (values["SSL_KEY_PATH"] == null) {
      keyString = "";
    }

    var contents = """
import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/commands/starter.dart';
import 'package:___PACKAGE_NAME___/___LIBRARY_NAME___.dart';

Future main(List<String> args, dynamic sendPort) async {
    var app = new Application<___CHANNEL_TYPE___>();
    var config = new ApplicationOptions()
      ..port = ___PORT___
      $certificateString
      $keyString
      $addressString
      $configString
      ..isIpv6Only = ___IPV6_ONLY___;

    app.options = config;
    
    await startApplication(app, $numberOfIsolates, sendPort);
}
    """;

    return contents.replaceAllMapped(new RegExp("___([A-Za-z0-9_-]+)___"), (match) {
      return values[match.group(1)];
    });
  }

  @override
  String get name {
    return "serve";
  }

  @override
  String get description {
    return "Runs Aqueduct applications.";
  }
}

Future<bool> supportsLaunchObservatory() async {
  String locator = Platform.isWindows ? "where" : "which";
  var result = await Process.run(locator, ["open"]);

  return result.exitCode == 0;
}

Future launchObservatory(String url) {
  return Process.run("open", [url]);
}
