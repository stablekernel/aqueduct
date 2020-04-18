import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/running_process.dart';

class CLIServer extends CLICommand with CLIProject {
  String derivedChannelType;

  @Option("timeout",
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

  @Flag("observe", help: "Enables Dart Observatory", defaultsTo: false)
  bool get shouldRunObservatory => decode("observe");

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
  int get numberOfIsolates => decode("isolates") ?? 0;

  @Option("address",
      abbr: "a",
      help:
          "The address to listen on. See HttpServer.bind for more details; this value is used as the String passed to InternetAddress.lookup."
          " Using the default will listen on any address.")
  String get address => decode("address");

  @Option("channel",
      abbr: "s",
      help:
          "The name of the ApplicationChannel subclass to be instantiated to serve requests. "
          "By default, this subclass is determined by reflecting on the application library in the [directory] being served.")
  String get channelType => decode("channel") ?? derivedChannelType;

  @Option("config-path",
      abbr: "c",
      help:
          "The path to a configuration file. This File is available in the ApplicationOptions"
          "for a ApplicationChannel to use to read application-specific configuration values. Relative paths are relative to [directory].",
      defaultsTo: "config.yaml")
  File get configurationFile => File(decode("config-path")).absolute;

  ReceivePort messagePort;
  ReceivePort errorPort;
  Completer<int> exitCode = Completer<int>();

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
      "CONFIGURATION_FILE_PATH": configurationFile.path,
      "SSL_KEY_PATH": keyPath,
      "SSL_CERTIFICATE_PATH": certificatePath,
      "NUMBER_OF_ISOLATES": numberOfIsolates
    };

    displayInfo("Starting application '$packageName/$libraryName'");
    displayProgress("Channel: $channelType");
    displayProgress("Config: ${configurationFile?.path}");
    displayProgress("Port: $port");

    errorPort = ReceivePort();
    messagePort = ReceivePort();

    final generatedStartScript = createScriptSource(replacements);
    final dataUri = Uri.parse(
        "data:application/dart;charset=utf-8,${Uri.encodeComponent(generatedStartScript)}");
    final startupCompleter = Completer<SendPort>();

    final isolate = await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        packageConfig: fileInProjectDirectory(".packages").uri,
        paused: true);

    errorPort.listen((msg) {
      if (msg is List) {
        startupCompleter.completeError(
            msg.first, StackTrace.fromString(msg.last as String));
      }
    });

    messagePort.listen((msg) {
      final message = msg as Map<dynamic, dynamic>;
      switch (message["status"] as String) {
        case "ok":
          {
            startupCompleter.complete(message["port"] as SendPort);
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

    final sendPort = await startupCompleter.future
        .timeout(Duration(seconds: startupTimeout));
    final process = StoppableProcess((reason) async {
      displayInfo("Stopping application.");
      displayProgress("Reason: $reason");
      sendPort.send({"command": "stop"});
    });

    return process;
  }

  Future prepare() async {
    if (keyPath != null && certificatePath == null) {
      throw CLIException(
          "Configuration error: --ssl-key-path was specified, but --ssl-certificate-path was not.");
    }
    if (keyPath == null && certificatePath != null) {
      throw CLIException(
          "Configuration error: --ssl-certificate-path was specified, but --ssl-key-path was not.");
    }

    displayInfo("Preparing...");
    derivedChannelType = await getChannelName();
  }

  String createScriptSource(Map<String, dynamic> values) {
    var addressString = "..address = \"___ADDRESS___\"";
    if (values["ADDRESS"] == null) {
      addressString = "";
    }
    var configString =
        "..configurationFilePath = r\"___CONFIGURATION_FILE_PATH___\"";
    if (values["CONFIGURATION_FILE_PATH"] == null) {
      configString = "";
    }
    var certificateString =
        "..certificateFilePath = r\"___SSL_CERTIFICATE_PATH___\"";
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
import 'package:aqueduct/src/cli/starter.dart';
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
    
    await startApplication(app, ${values['NUMBER_OF_ISOLATES']}, sendPort);
}
    """;

    return contents.replaceAllMapped(RegExp("___([A-Za-z0-9_-]+)___"), (match) {
      return values[match.group(1)].toString();
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
