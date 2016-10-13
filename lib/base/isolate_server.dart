part of aqueduct;

class _Server {
  ApplicationInstanceConfiguration configuration;
  HttpServer server;
  RequestSink stream;
  int identifier;
  Logger get logger => new Logger("aqueduct");

  _Server(this.stream, this.configuration, this.identifier) {
    stream.server = this;
  }

  Future start() async {
    try {
      stream.addRoutes();
      stream.router?.finalize();
      stream.nextController = stream.initialController();

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

    await stream.willOpen();

    server.map((baseReq) => new Request(baseReq)).listen((Request req) async {
      logger.fine("Request received $req.", req);
      await stream.willReceiveRequest(req);
      stream.receive(req);
    });

    stream.didOpen();
  }
}

class IsolateServer extends _Server {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;

  IsolateServer(RequestSink sink, ApplicationInstanceConfiguration configuration, int identifier, this.supervisingApplicationPort)
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
    if (message == IsolateSupervisor._MessageStop) {
      server.close(force: true).then((s) {
        supervisingApplicationPort.send(IsolateSupervisor._MessageStop);
      });
    }
  }
}

void isolateServerEntryPoint(InitialServerMessage params) {
  var sinkSourceLibraryMirror = currentMirrorSystem().libraries[params.streamLibraryURI];
  var sinkTypeMirror = sinkSourceLibraryMirror.declarations[new Symbol(params.streamTypeName)] as ClassMirror;

  var app = sinkTypeMirror
      .newInstance(new Symbol(""), [params.configuration.configurationOptions])
      .reflectee;

  var server = new IsolateServer(app, params.configuration, params.identifier, params.parentMessagePort);
  server.start();
}