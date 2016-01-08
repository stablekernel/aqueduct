part of monadart;

class Server {
  ApplicationInstanceConfiguration configuration;
  HttpServer server;
  ApplicationPipeline pipeline;
  int identifier;

  Server(this.pipeline, this.configuration, this.identifier) {

  }

  Future start() async {
    pipeline.addRoutes();
    pipeline.nextHandler = pipeline.initialHandler();

    HttpServer s = null;
    if (configuration.securityContext != null) {
      s = await HttpServer.bindSecure(configuration.address, configuration.port, configuration.securityContext,
          requestClientCertificate: configuration.isUsingClientCertificate,
          v6Only: configuration.isIpv6Only,
          shared: configuration._shared);
    } else {
      s = await HttpServer.bind(configuration.address, configuration.port,
          v6Only: configuration.isIpv6Only,
          shared: configuration._shared);
    }

    s.autoCompress = true;
    await didOpen(s);
  }

  Future didOpen(HttpServer s) async {
    new Logger("monadart").info("Server monadart/$identifier started.");

    server = s;

    server.serverHeader = "monadart/${this.identifier}";

    await pipeline.willOpen();

    server.map((baseReq) => new ResourceRequest(baseReq)).listen((ResourceRequest req) async {
      new Logger("monadart").info("Request received $req.");
      await pipeline.willReceiveRequest(req);
      pipeline.deliver(req);
    });

    pipeline.didOpen();
  }
}

class IsolateServer extends Server {
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;

  IsolateServer(ApplicationPipeline pipeline, ApplicationInstanceConfiguration configuration, int identifier, this.supervisingApplicationPort)
    : super(pipeline, configuration, identifier) {
    supervisingReceivePort = new ReceivePort();
    supervisingReceivePort.listen(listener);
  }

  @override
  Future didOpen(HttpServer s) async {
    await super.didOpen(s);
    supervisingApplicationPort.send(supervisingReceivePort.sendPort);
  }

  void listener(dynamic message) {
    if (message == IsolateSupervisor._MessageStop) {
      server.close().then((s) {
        supervisingApplicationPort.send(IsolateSupervisor._MessageStop);
      });
    }
  }

  static void entry(_InitialServerMessage params) {
    var pipelineSourceLibraryMirror = currentMirrorSystem().libraries[params.pipelineLibraryURI];
    var pipelineTypeMirror = pipelineSourceLibraryMirror.declarations[new Symbol(params.pipelineTypeName)] as ClassMirror;

    var app = pipelineTypeMirror.newInstance(new Symbol(""), [params.configuration.pipelineOptions]).reflectee;
    var server = new IsolateServer(app, params.configuration, params.identifier, params.parentMessagePort);

    server.start();
  }
}
