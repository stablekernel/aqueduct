part of monadart;

class IsolateSupervisor {

  static String _MessageStop = "_MessageStop";

  final Isolate isolate;
  final ReceivePort receivePort;
  final int identifier;

  SendPort _serverSendPort;

  Completer _launchCompleter;
  Completer _stopCompleter;

  IsolateSupervisor(this.isolate, this.receivePort, this.identifier) {
  }

  Future resume() {
    _launchCompleter = new Completer();
    receivePort.listen(listener);

    isolate.resume(isolate.pauseCapability);
    return _launchCompleter.future.timeout(new Duration(seconds: 30));
  }

  Future stop() {
    _stopCompleter = new Completer();
    _serverSendPort.send(_MessageStop);
    return _stopCompleter.future.timeout(new Duration(seconds: 30));
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _launchCompleter.complete();
      _launchCompleter = null;

      _serverSendPort = message;
    } else if (message == _MessageStop) {
      _stopCompleter.complete();
      _stopCompleter = null;
    }
  }
}
