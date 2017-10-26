import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../utilities/resource_registry.dart';
import 'application.dart';
import 'application_configuration.dart';
import 'isolate_supervisor.dart';

class ApplicationIsolateServer extends ApplicationServer {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;
  bool logToConsole;

  ApplicationIsolateServer(ClassMirror requestSinkType, ApplicationConfiguration configuration, int identifier,
      this.supervisingApplicationPort, this.logToConsole)
      : super(requestSinkType, configuration, identifier) {
    if (logToConsole) {
      hierarchicalLoggingEnabled = true;
      logger.level = Level.ALL;
      logger.onRecord.listen((r) => print(r));
    }
    supervisingReceivePort = new ReceivePort();
    supervisingReceivePort.listen(listener);

    logger.fine("ApplicationIsolateServer($identifier) listening, sending port");
    supervisingApplicationPort.send(supervisingReceivePort.sendPort);
  }

  @override
  Future start({bool shareHttpServer: false}) async {
    var result = await super.start(shareHttpServer: shareHttpServer);
    logger.fine("ApplicationIsolateServer($identifier) started, sending listen message");
    supervisingApplicationPort.send(ApplicationIsolateSupervisor.MessageListening);

    return result;
  }

  @override
  void sendApplicationEvent(dynamic event) {
    try {
      supervisingApplicationPort.send(new MessageHubMessage(event));
    } catch (e, st) {
      hubSink?.addError(e, st);
    }
  }

  void listener(dynamic message) {
    if (message == ApplicationIsolateSupervisor.MessageStop) {
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
    logger.fine("ApplicationIsolateServer($identifier) sending stop acknowledgement");
    supervisingApplicationPort.send(ApplicationIsolateSupervisor.MessageStop);
  }
}

/// This method is used internally.
void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  var sinkSourceLibraryMirror = currentMirrorSystem().libraries[params.streamLibraryURI];
  var sinkTypeMirror = sinkSourceLibraryMirror.declarations[new Symbol(params.streamTypeName)] as ClassMirror;

  var server = new ApplicationIsolateServer(sinkTypeMirror,
      params.configuration, params.identifier, params.parentMessagePort, params.logToConsole);

  server.start(shareHttpServer: true);
}

class ApplicationInitialServerMessage {
  String streamTypeName;
  Uri streamLibraryURI;
  ApplicationConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;
  bool logToConsole = false;

  ApplicationInitialServerMessage(
      this.streamTypeName, this.streamLibraryURI, this.configuration, this.identifier, this.parentMessagePort,
      {this.logToConsole: false});
}

class MessageHubMessage {
  MessageHubMessage(this.payload);

  dynamic payload;
}
