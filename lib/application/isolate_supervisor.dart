part of aqueduct;

/// Represents the supervision of a [_IsolateServer].
///
/// You should not use this class directly.
class ApplicationIsolateSupervisor {
  static String _MessageStop = "_MessageStop";

  /// Create an isntance of [ApplicationIsolateSupervisor].
  ApplicationIsolateSupervisor(this.supervisingApplication, this.isolate, this.receivePort, this.identifier, this.logger);

  /// The [Isolate] being supervised.
  final Isolate isolate;

  /// The [ReceivePort] for which messages coming from [isolate] will be received.
  final ReceivePort receivePort;

  /// A numeric identifier for the isolate relative to the [Application].
  final int identifier;

  /// A reference to the owning [Application]
  Application supervisingApplication;

  /// A reference to the [Logger] used by the [supervisingApplication].
  Logger logger;

  SendPort _serverSendPort;
  Completer _launchCompleter;
  Completer _stopCompleter;

  /// Resumes the [Isolate] being supervised.
  Future resume() {
    _launchCompleter = new Completer();
    receivePort.listen(listener);

    isolate.setErrorsFatal(false);
    isolate.resume(isolate.pauseCapability);

    return _launchCompleter.future.timeout(new Duration(seconds: 30));
  }

  /// Stops the [Isolate] being supervised.
  Future stop() async {
    _stopCompleter = new Completer();
    _serverSendPort.send(_MessageStop);
    await _stopCompleter.future.timeout(new Duration(seconds: 30));

    isolate.kill();
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _launchCompleter.complete();
      _launchCompleter = null;

      _serverSendPort = message;
    } else if (message == _MessageStop) {
      _stopCompleter?.complete();
      _stopCompleter = null;
    } else if (message is List) {
      if (_launchCompleter != null) {
        _launchCompleter.completeError(new ApplicationSupervisorException(message.first), new StackTrace.fromString(message.last));
      } else {
        _tearDownWithError(message.first, message.last);
      }
    }
  }

  void _tearDownWithError(String errorMessage, String stackTrace) {
    stop().then((_) {
      _launchCompleter = null;
      _stopCompleter = null;
      supervisingApplication.isolateDidExitWithError(this, errorMessage, new StackTrace.fromString(stackTrace));
    });
  }
}

/// An exception originating from an [Isolate] within an [Application].
class ApplicationSupervisorException implements Exception {
  ApplicationSupervisorException(this.message);

  final String message;

  String toString() {
    return "$message";
  }
}
