import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:aqueduct/src/application/service_registry.dart';
import 'package:logging/logging.dart';

import 'application.dart';
import 'isolate_supervisor.dart';
import 'options.dart';

class ApplicationIsolateServer extends ApplicationServer {
  ApplicationIsolateServer(
      ClassMirror channelType,
      ApplicationOptions configuration,
      int identifier,
      this.supervisingApplicationPort,
      {bool logToConsole = false})
      : super(channelType, configuration, identifier) {
    if (logToConsole) {
      hierarchicalLoggingEnabled = true;
      logger.level = Level.ALL;
      logger.onRecord.listen(print);
    }
    supervisingReceivePort = ReceivePort();
    supervisingReceivePort.listen(listener);

    logger
        .fine("ApplicationIsolateServer($identifier) listening, sending port");
    supervisingApplicationPort.send(supervisingReceivePort.sendPort);
  }

  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;

  @override
  Future start({bool shareHttpServer = false}) async {
    final result = await super.start(shareHttpServer: shareHttpServer);
    logger.fine(
        "ApplicationIsolateServer($identifier) started, sending listen message");
    supervisingApplicationPort
        .send(ApplicationIsolateSupervisor.messageKeyListening);

    return result;
  }

  @override
  void sendApplicationEvent(dynamic event) {
    try {
      supervisingApplicationPort.send(MessageHubMessage(event));
    } catch (e, st) {
      hubSink?.addError(e, st);
    }
  }

  void listener(dynamic message) {
    if (message == ApplicationIsolateSupervisor.messageKeyStop) {
      stop();
    } else if (message is MessageHubMessage) {
      hubSink?.add(message.payload);
    }
  }

  Future stop() async {
    supervisingReceivePort.close();
    logger.fine("ApplicationIsolateServer($identifier) closing server");
    await close();
    logger.fine("ApplicationIsolateServer($identifier) did close server");
    await ServiceRegistry.defaultInstance.close();
    logger.clearListeners();
    logger.fine(
        "ApplicationIsolateServer($identifier) sending stop acknowledgement");
    supervisingApplicationPort
        .send(ApplicationIsolateSupervisor.messageKeyStop);
  }
}

void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  final channelSourceLibrary =
      currentMirrorSystem().libraries[params.streamLibraryURI];
  final channelType = channelSourceLibrary
      .declarations[Symbol(params.streamTypeName)] as ClassMirror;

  final server = ApplicationIsolateServer(channelType, params.configuration,
      params.identifier, params.parentMessagePort,
      logToConsole: params.logToConsole);

  server.start(shareHttpServer: true);
}

class ApplicationInitialServerMessage {
  ApplicationInitialServerMessage(this.streamTypeName, this.streamLibraryURI,
      this.configuration, this.identifier, this.parentMessagePort,
      {this.logToConsole = false});

  String streamTypeName;
  Uri streamLibraryURI;
  ApplicationOptions configuration;
  SendPort parentMessagePort;
  int identifier;
  bool logToConsole = false;
}

class MessageHubMessage {
  MessageHubMessage(this.payload);

  dynamic payload;
}
