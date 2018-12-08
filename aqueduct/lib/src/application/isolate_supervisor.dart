import 'dart:async';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'application.dart';
import 'isolate_application_server.dart';

/// Represents the supervision of a [ApplicationIsolateServer].
///
/// You should not use this class directly.
class ApplicationIsolateSupervisor {
  /// Create an instance of [ApplicationIsolateSupervisor].
  ApplicationIsolateSupervisor(this.supervisingApplication, this.isolate,
      this.receivePort, this.identifier, this.logger,
      {this.startupTimeout = const Duration(seconds: 30)});

  /// The [Isolate] being supervised.
  final Isolate isolate;

  /// The [ReceivePort] for which messages coming from [isolate] will be received.
  final ReceivePort receivePort;

  /// A numeric identifier for the isolate relative to the [Application].
  final int identifier;

  final Duration startupTimeout;

  /// A reference to the owning [Application]
  Application supervisingApplication;

  /// A reference to the [Logger] used by the [supervisingApplication].
  Logger logger;

  final List<MessageHubMessage> _pendingMessageQueue = [];

  bool get _isLaunching => _launchCompleter != null;
  SendPort _serverSendPort;
  Completer _launchCompleter;
  Completer _stopCompleter;

  static const String messageKeyStop = "_MessageStop";
  static const String messageKeyListening = "_MessageListening";

  /// Resumes the [Isolate] being supervised.
  Future resume() {
    _launchCompleter = Completer();
    receivePort.listen(listener);

    isolate.setErrorsFatal(false);
    isolate.addErrorListener(receivePort.sendPort);
    logger.fine(
        "ApplicationIsolateSupervisor($identifier).resume will resume isolate");
    isolate.resume(isolate.pauseCapability);

    return _launchCompleter.future.timeout(startupTimeout, onTimeout: () {
      logger.fine(
          "ApplicationIsolateSupervisor($identifier).resume timed out waiting for isolate start");
      throw TimeoutException(
          "Isolate ($identifier) failed to launch in $startupTimeout seconds. "
          "There may be an error with your application or Application.isolateStartupTimeout needs to be increased.");
    });
  }

  /// Stops the [Isolate] being supervised.
  Future stop() async {
    _stopCompleter = Completer();
    logger.fine(
        "ApplicationIsolateSupervisor($identifier).stop sending stop to supervised isolate");
    _serverSendPort.send(messageKeyStop);

    try {
      await _stopCompleter.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      logger?.severe(
          "Isolate ($identifier) not responding to stop message, terminating.");
      isolate.kill();
    }

    receivePort.close();
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _serverSendPort = message;
    } else if (message == messageKeyListening) {
      _launchCompleter.complete();
      _launchCompleter = null;
      logger.fine(
          "ApplicationIsolateSupervisor($identifier) isolate listening acknowledged");
    } else if (message == messageKeyStop) {
      logger.fine(
          "ApplicationIsolateSupervisor($identifier) stop message acknowledged");
      receivePort.close();

      _stopCompleter?.complete();
      _stopCompleter = null;
    } else if (message is List) {
      logger.fine(
          "ApplicationIsolateSupervisor($identifier) received isolate error ${message.first}");
      final stacktrace = StackTrace.fromString(message.last as String);
      _handleIsolateException(message.first, stacktrace);
    } else if (message is MessageHubMessage) {
      if (!supervisingApplication.isRunning) {
        _pendingMessageQueue.add(message);
      } else {
        _sendMessageToOtherSupervisors(message);
      }
    }
  }

  void sendPendingMessages() {
    final list = List<MessageHubMessage>.from(_pendingMessageQueue);
    _pendingMessageQueue.clear();
    list.forEach(_sendMessageToOtherSupervisors);
  }

  void _sendMessageToOtherSupervisors(MessageHubMessage message) {
    supervisingApplication.supervisors
        .where((sup) => sup != this)
        .forEach((supervisor) {
      supervisor._serverSendPort.send(message);
    });
  }

  void _handleIsolateException(dynamic error, StackTrace stacktrace) {
    if (_isLaunching) {
      final appException = ApplicationStartupException(error);
      _launchCompleter.completeError(appException, stacktrace);
    } else {
      logger.severe("Uncaught exception in isolate.", error, stacktrace);
    }
  }
}
