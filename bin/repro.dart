import 'dart:async';
import 'dart:isolate';

Future main() async {
  var receivePort = new ReceivePort();
  var isolate = await Isolate.spawn(entry, receivePort.sendPort, paused: true);
  var sup = new Supervisor(isolate, receivePort);

  var completer = new Completer();
  var receivePort = new ReceivePort();
  receivePort.listen((msg) {
    if (msg == "ack") {
      completer.complete();
    }
  });


  isolate.setErrorsFatal(false);
  isolate.resume(isolate.pauseCapability);
  isolate.addErrorListener(receivePort.sendPort);

  await completer.future.timeout(new Duration(seconds: 2));
  receivePort.close();
}

void entry(SendPort msg) {
  new Future.delayed(new Duration(seconds: 4), () {
    msg.send("ack");
  });
}

class Supervisor {
  Supervisor(this.isolate, this.receivePort);
  Isolate isolate;
  ReceivePort receivePort;
  Completer _launchCompleter;

  Future resume() {
    _launchCompleter = new Completer();
    receivePort.listen(listener);

    isolate.setErrorsFatal(false);
    isolate.resume(isolate.pauseCapability);
    isolate.addErrorListener(receivePort.sendPort);

    return _launchCompleter.future.timeout(new Duration(seconds: 2), onTimeout: () {
      receivePort.close();
      throw new TimeoutException("rethrow");
    });
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _launchCompleter.complete();
      _launchCompleter = null;
    }
  }
}