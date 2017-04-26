import 'dart:async';
import 'dart:isolate';
import 'dart:io';

Future main() async {
  for (var i = 0; i < 2; i++) {
    var receivePort = new ReceivePort();
    var isolate = await Isolate.spawn(entry, [receivePort.sendPort, i], paused: true);
    var sup = new Supervisor(isolate, receivePort);

    await sup.resume();
    print("$i started");
  }
}

void entry(List msg) {
  SendPort sendPort = msg.first;
  var id = msg.last;
  var server = new IsolateServer(sendPort);
  server.start(id);
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

  HttpServer server;
  ReceivePort supervisingReceivePort;
  SendPort supervisingApplicationPort;

  void start(int id) {
    if (id == 0) {
      HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 4040).then((s) {
        server = s;
        server.listen((req) {
          req.response.close();
        });
      });
      supervisingApplicationPort.send(supervisingReceivePort.sendPort);
    } else {
      new Future.delayed(new Duration(seconds: 4), () {
        supervisingApplicationPort.send(supervisingReceivePort.sendPort);
      });
    }
  }

  void listener(dynamic message) {
    if (message == "stop") {
      supervisingReceivePort.close();
      server?.close(force: true)?.then((_) {
        supervisingApplicationPort.send("stop");
      });
    }
  }
}