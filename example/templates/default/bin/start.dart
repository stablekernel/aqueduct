import 'package:wildfire/wildfire.dart';
import 'dart:io';
import 'dart:async';

main() async {
  try {
    var configFileName = "config.yaml";
    var logPath = "api.log";

    var config = new WildfireConfiguration(configFileName);
    var logger = new LoggingServer([new RotatingLoggingBackend(logPath)]);
    await logger.start();

    var app = new Application<WildfirePipeline>();
    app.configuration.port = config.port;
    app.configuration.pipelineOptions = {
      WildfirePipeline.LoggingTargetKey : logger.getNewTarget(),
      WildfirePipeline.ConfigurationKey : config
    };

    await app.start(numberOfInstances: 3);

    var signalPath = new File(".aqueductsignal");
    await signalPath.writeAsString("ok");
  } on IsolateSupervisorException catch (e, st) {
    await writeError("IsolateSupervisorException, server failed to start: ${e.message} $st");
  } catch (e, st) {
    await writeError("Server failed to start: $e $st");
  }
}

Future writeError(String error) async {
  var file = new File("error.log");
  await file.writeAsString(error);
}
