import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';

/*
  Warning: do not remove. This method is invoked by a generated script.

 */
Future startApplication<T extends ApplicationChannel>(
    Application<T> app, int isolateCount, SendPort parentPort) async {
  final port = ReceivePort();

  port.listen((msg) {
    if (msg["command"] == "stop") {
      port.close();
      app.stop().then((_) {
        parentPort.send({"status": "stopped"});
      });
    }
  });

  if (isolateCount == 0) {
    await app.startOnCurrentIsolate();
  } else {
    await app.start(numberOfInstances: isolateCount);
  }
  parentPort.send({"status": "ok", "port": port.sendPort});
}
