import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../http/request_sink.dart';
import '../utilities/resource_registry.dart';
import 'application.dart';
import 'application_configuration.dart';
import 'isolate_supervisor.dart';

class ApplicationIsolateServer extends ApplicationServer {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;
  bool logToConsole;

  ApplicationIsolateServer(
      ApplicationConfiguration configuration,
      int identifier,
      this.supervisingApplicationPort, this.logToConsole)
      : super(configuration, identifier) {
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
  Future start(RequestSink sink, {bool shareHttpServer: false}) async {
    var result = await super.start(sink, shareHttpServer: shareHttpServer);
    logger.fine("ApplicationIsolateServer($identifier) started, sending listen message");
    supervisingApplicationPort.send(ApplicationIsolateSupervisor.MessageListening);

    return result;
  }

  void listener(dynamic message) {
    if (message == ApplicationIsolateSupervisor.MessageStop) {
      stop();
    }
  }

  Future stop() async {
    supervisingReceivePort.close();
    await close();
    await ResourceRegistry.release();
    logger.clearListeners();
    supervisingApplicationPort
        .send(ApplicationIsolateSupervisor.MessageStop);
  }
}

/// This method is used internally.
void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  var server = new ApplicationIsolateServer(
      params.configuration, params.identifier, params.parentMessagePort, params.logToConsole);

  var sinkSourceLibraryMirror =
  currentMirrorSystem().libraries[params.streamLibraryURI];
  var sinkTypeMirror = sinkSourceLibraryMirror
      .declarations[new Symbol(params.streamTypeName)] as ClassMirror;

  RequestSink sink = sinkTypeMirror
      .newInstance(new Symbol(""), [params.configuration]).reflectee;

  server.start(sink, shareHttpServer: true);
}

class ApplicationInitialServerMessage {
  String streamTypeName;
  Uri streamLibraryURI;
  ApplicationConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;
  bool logToConsole = false;

  ApplicationInitialServerMessage(this.streamTypeName, this.streamLibraryURI,
      this.configuration, this.identifier, this.parentMessagePort, {this.logToConsole: false});
}
