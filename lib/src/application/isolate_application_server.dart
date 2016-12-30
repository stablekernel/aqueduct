import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';

import '../http/request_sink.dart';
import 'application.dart';
import 'application_configuration.dart';
import 'isolate_supervisor.dart';

class ApplicationIsolateServer extends ApplicationServer {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;

  ApplicationIsolateServer(
      RequestSink sink,
      ApplicationConfiguration configuration,
      int identifier,
      this.supervisingApplicationPort)
      : super(sink, configuration, identifier) {
    sink.server = this;
    supervisingReceivePort = new ReceivePort();
    supervisingReceivePort.listen(listener);
  }

  @override
  Future didOpen() async {
    await super.didOpen();

    supervisingApplicationPort.send(supervisingReceivePort.sendPort);
  }

  void listener(dynamic message) {
    if (message == ApplicationIsolateSupervisor.MessageStop) {
      server.close(force: true).then((s) {
        supervisingApplicationPort
            .send(ApplicationIsolateSupervisor.MessageStop);
      });
    }
  }
}

/// This method is used internally.
void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  RequestSink sink;
  try {
    var sinkSourceLibraryMirror =
        currentMirrorSystem().libraries[params.streamLibraryURI];
    var sinkTypeMirror = sinkSourceLibraryMirror
        .declarations[new Symbol(params.streamTypeName)] as ClassMirror;

    sink = sinkTypeMirror.newInstance(
        new Symbol(""), [params.configuration]).reflectee;
  } catch (e, st) {
    params.parentMessagePort.send([e, st.toString()]);

    return;
  }

  var server = new ApplicationIsolateServer(
      sink, params.configuration, params.identifier, params.parentMessagePort);
  server.start(shareHttpServer: true);
}

class ApplicationInitialServerMessage {
  String streamTypeName;
  Uri streamLibraryURI;
  ApplicationConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;

  ApplicationInitialServerMessage(this.streamTypeName, this.streamLibraryURI,
      this.configuration, this.identifier, this.parentMessagePort);
}
