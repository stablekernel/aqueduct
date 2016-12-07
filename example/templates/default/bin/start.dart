import 'dart:async';
import 'dart:io';

import 'package:wildfire/wildfire.dart';

main() async {
  try {
    var configFileName = "config.yaml";
    var logPath = "api.log";

    var config = new WildfireConfiguration(configFileName);
    var logger = new LoggingServer([new RotatingLoggingBackend(logPath)]);
    await logger.start();

    var app = new Application<WildfireSink>();
    app.configuration.port = config.port;
    app.configuration.configurationOptions = {
      WildfireSink.LoggingTargetKey: logger.getNewTarget(),
      WildfireSink.ConfigurationKey: config
    };

    await app.start(numberOfInstances: 3);

    var signalPath = new File(".aqueductsignal");
    await signalPath.writeAsString("ok");
  } catch (e, st) {
    await writeError("Server failed to start: $e $st");
  }
}

Future writeError(String error) async {
  var file = new File("error.log");
  await file.writeAsString(error);
}
