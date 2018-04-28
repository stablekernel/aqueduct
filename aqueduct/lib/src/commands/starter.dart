import 'dart:async';
import 'dart:isolate';

import 'package:aqueduct/aqueduct.dart';

Future startApplication<T extends ApplicationChannel>(Application<T> app, int isolateCount, SendPort parentPort) async {
  final port = new ReceivePort();

  port.listen((msg) {
    if (msg["command"] == "stop") {
      port.close();
      app.stop().then((_) {
        parentPort.send({"status": "stopped"});
      });
    }
  });

  await app.start(numberOfInstances: isolateCount);
  parentPort.send({"status": "ok", "port": port.sendPort});
}
