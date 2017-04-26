import 'dart:async';
import 'dart:isolate';
import 'dart:io';

Future main() async {
  var completer = new Completer();
  var receivePort = new ReceivePort();
  receivePort.listen((msg) {
    if (msg == "ack") {
      completer.complete();
    }
  });

  var isolate = await Isolate.spawn(entry, receivePort.sendPort);

  await completer.future.timeout(new Duration(seconds: 2));
  receivePort.close();
}

void entry(SendPort msg) {
  new Future.delayed(new Duration(seconds: 4), () {
    msg.send("ack");
  });
}