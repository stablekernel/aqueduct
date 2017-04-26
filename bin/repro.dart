import 'dart:async';
import 'dart:isolate';

Future main() async {
  for (var i = 0; i < 2; i++) {
    var receivePort = new ReceivePort();
    var isolate = await Isolate.spawn(entry, receivePort.sendPort, paused: true);
    var sup = new Supervisor(isolate, receivePort);

    await sup.resume();
  }
}

void entry(SendPort msg) {
  var server = new IsolateServer(msg);
  new Future.delayed(new Duration(seconds: 4), () {
    msg.send(server.supervisingReceivePort.sendPort);
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

class IsolateServer {
  IsolateServer(this.supervisingApplicationPort) {
    supervisingReceivePort = new ReceivePort();
    supervisingReceivePort.listen(listener);
  }

  ReceivePort supervisingReceivePort;
  SendPort supervisingApplicationPort;

  void listener(dynamic message) {
    if (message == "stop") {
      supervisingReceivePort.close();

      supervisingApplicationPort.send("stop");
    }
  }
}