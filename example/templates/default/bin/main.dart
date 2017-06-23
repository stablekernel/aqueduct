import 'package:wildfire/wildfire.dart';

Future main() async {
  var app = new Application<WildfireSink>()
      ..configuration.configurationFilePath = "config.yaml"
      ..configuration.port = 8081;

  await app.start(numberOfInstances: 2);

  print("Application started on port: ${app.configuration.port}.");
  print("Use Ctrl-C (SIGINT) to stop running the application.");
}