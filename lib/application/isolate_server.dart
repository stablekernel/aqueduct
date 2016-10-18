part of aqueduct;

/// Used internally.
class ApplicationServer {
  ApplicationConfiguration configuration;
  HttpServer server;
  RequestSink sink;
  int identifier;
  Logger get logger => new Logger("aqueduct");

  ApplicationServer(this.sink, this.configuration, this.identifier) {
    sink.server = this;
  }

  Future start() async {
    try {
      sink.setupRouter(sink.router);
      sink.router?.finalize();
      sink.nextController = sink.initialController;

      if (configuration.securityContext != null) {
        server = await HttpServer.bindSecure(configuration.address, configuration.port, configuration.securityContext,
            requestClientCertificate: configuration.isUsingClientCertificate,
            v6Only: configuration.isIpv6Only,
            shared: configuration._shared);
      } else {
        server = await HttpServer.bind(configuration.address, configuration.port,
            v6Only: configuration.isIpv6Only,
            shared: configuration._shared);
      }

      server.autoCompress = true;
      await didOpen();
    } catch (e) {
      await server?.close(force: true);
      rethrow;
    }
  }

  Future didOpen() async {
    logger.info("Server aqueduct/$identifier started.");

    server.serverHeader = "aqueduct/${this.identifier}";

    await sink.willOpen();

    server.map((baseReq) => new Request(baseReq)).listen((Request req) async {
      logger.fine("Request received $req.", req);
      await sink.willReceiveRequest(req);
      sink.receive(req);
    });

    sink.didOpen();
  }
}

/// Used internally.
class ApplicationIsolateServer extends ApplicationServer {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;

  ApplicationIsolateServer(RequestSink sink, ApplicationConfiguration configuration, int identifier, this.supervisingApplicationPort)
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
    if (message == ApplicationIsolateSupervisor._MessageStop) {
      server.close(force: true).then((s) {
        supervisingApplicationPort.send(ApplicationIsolateSupervisor._MessageStop);
      });
    }
  }
}

/// This method is used internally.
void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  var sinkSourceLibraryMirror = currentMirrorSystem().libraries[params.streamLibraryURI];
  var sinkTypeMirror = sinkSourceLibraryMirror.declarations[new Symbol(params.streamTypeName)] as ClassMirror;

  var app = sinkTypeMirror
      .newInstance(new Symbol(""), [params.configuration.configurationOptions])
      .reflectee;

  var server = new ApplicationIsolateServer(app, params.configuration, params.identifier, params.parentMessagePort);
  server.start();
}