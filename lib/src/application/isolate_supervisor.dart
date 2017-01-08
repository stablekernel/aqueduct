import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'application.dart';

/// Represents the supervision of a [ApplicationIsolateServer].
///
/// You should not use this class directly.
class ApplicationIsolateSupervisor {
  static const String MessageStop = "_MessageStop";

  /// Create an isntance of [ApplicationIsolateSupervisor].
  ApplicationIsolateSupervisor(this.supervisingApplication, this.isolate,
      this.receivePort, this.identifier, this.logger);

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

  bool get _isLaunching => _launchCompleter != null;
  SendPort _serverSendPort;
  Completer _launchCompleter;
  Completer _stopCompleter;

  /// Resumes the [Isolate] being supervised.
  Future resume() {
    _launchCompleter = new Completer();
    receivePort.listen(listener);

    isolate.setErrorsFatal(false);
    isolate.resume(isolate.pauseCapability);

    return _launchCompleter.future.timeout(new Duration(seconds: 30),
        onTimeout: () {
      receivePort.close();
      throw new TimeoutException("Isolate failed to launch in 30 seconds.");
    });
  }

  /// Stops the [Isolate] being supervised.
  Future stop() async {
    _stopCompleter = new Completer();
    _serverSendPort.send(MessageStop);
    await _stopCompleter.future.timeout(new Duration(seconds: 30));
    receivePort.close();

    isolate.kill();
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _launchCompleter.complete();
      _launchCompleter = null;

      _serverSendPort = message;
    } else if (message == MessageStop) {
      _stopCompleter?.complete();
      _stopCompleter = null;
    } else if (message is List) {
      var stacktrace = new StackTrace.fromString(message.last);
      _handleIsolateException(message.first, stacktrace);
    }
  }

  void _handleIsolateException(dynamic error, StackTrace stacktrace) {
    if (_isLaunching) {
      receivePort.close();

      var appException = new ApplicationStartupException(error);
      _launchCompleter.completeError(appException, stacktrace);
    } else {
      logger.severe("Uncaught exception in isolate.", error, stacktrace);
    }
  }
}
