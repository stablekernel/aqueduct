import 'package:wildfire/wildfire.dart';

Future main() async {
  var app = new Application<WildfireChannel>()
      ..options.configurationFilePath = "config.yaml"
      ..options.port = 8000;

  await app.start(numberOfInstances: 2);

  print("Application started on port: ${app.options.port}.");
  print("Use Ctrl-C (SIGINT) to stop running the application.");
}