part of monadart;

class ApplicationInstanceConfiguration {
  int identifier;

  dynamic address;
  int port = 8080;
  bool isIpv6Only = false;
  bool isUsingClientCertificate = false;
  String serverCertificateName = null;
  bool shared = false;

  ApplicationInstanceConfiguration();
  ApplicationInstanceConfiguration.fromConfiguration(
      ApplicationInstanceConfiguration config)
      : this.identifier = config.identifier,
        this.address = config.address,
        this.port = config.port,
        this.isIpv6Only = config.isIpv6Only,
        this.isUsingClientCertificate = config.isUsingClientCertificate,
        this.serverCertificateName = config.serverCertificateName,
        this.shared = config.shared;
}

abstract class ApplicationPipeline {
  void attachTo(Stream<ResourceRequest> requestStream);
}

class Application {
  List<_ServerRecord> servers = [];

  ApplicationInstanceConfiguration configuration =
      new ApplicationInstanceConfiguration();
  Type pipelineType;

  Future start({int numberOfInstances: 1}) async {
    if (configuration.address == null) {
      if (configuration.isIpv6Only) {
        configuration.address = InternetAddress.ANY_IP_V6;
      } else {
        configuration.address = InternetAddress.ANY_IP_V4;
      }
    }

    configuration.shared = numberOfInstances > 1;

    for (int i = 0; i < numberOfInstances; i++) {
      var config =
          new ApplicationInstanceConfiguration.fromConfiguration(configuration);
      config.identifier = i + 1;

      var serverRecord = await spawn(config);
      servers.add(serverRecord);
    }

    servers.forEach((i) {
      i.resume();
    });
  }

  Future<_ServerRecord> spawn(ApplicationInstanceConfiguration config) async {
    var receivePort = new ReceivePort();

    var pipelineTypeMirror = reflectType(pipelineType);
    var pipelineLibraryURI = (pipelineTypeMirror.owner as LibraryMirror).uri;
    var pipelineTypeName = MirrorSystem.getName(pipelineTypeMirror.simpleName);

    var initialMessage = new _InitialServerMessage(
        pipelineTypeName, pipelineLibraryURI, config, receivePort.sendPort);
    var isolate =
        await Isolate.spawn(_Server.entry, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new _ServerRecord(isolate, receivePort, config.identifier);
  }
}

class _RouteSpec {
  final Type controller;
  final String path;
  _RouteSpec(this.path, this.controller);
}

class _Server {
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  HttpServer server;
  ApplicationPipeline pipeline;

  _Server(this.pipeline, this.configuration, this.parentMessagePort);

  Future start() async {
    var onBind = (serv) {
      server = serv;

      server.serverHeader = "monadart/${configuration.identifier}";

      var stream = server.map((req) => new ResourceRequest(req));
      pipeline.attachTo(stream);
    };

    if (configuration.serverCertificateName != null) {
      HttpServer
          .bindSecure(configuration.address, configuration.port,
              certificateName: configuration.serverCertificateName,
              v6Only: configuration.isIpv6Only,
              shared: configuration.shared)
          .then(onBind);
    } else if (configuration.isUsingClientCertificate) {
      HttpServer
          .bindSecure(configuration.address, configuration.port,
              requestClientCertificate: true,
              v6Only: configuration.isIpv6Only,
              shared: configuration.shared)
          .then(onBind);
    } else {
      HttpServer
          .bind(configuration.address, configuration.port,
              v6Only: configuration.isIpv6Only, shared: configuration.shared)
          .then(onBind);
    }
  }

  static void entry(_InitialServerMessage params) {
    var pipelineSourceLibraryMirror =
        currentMirrorSystem().libraries[params.pipelineLibraryURI];
    var pipelineTypeMirror = pipelineSourceLibraryMirror.declarations[
        new Symbol(params.pipelineTypeName)] as ClassMirror;

    var app = pipelineTypeMirror.newInstance(new Symbol(""), []).reflectee;
    var server =
        new _Server(app, params.configuration, params.parentMessagePort);

    server.start();
  }
}

class _ServerRecord {
  final Isolate isolate;
  final ReceivePort receivePort;
  final int identifier;

  _ServerRecord(this.isolate, this.receivePort, this.identifier);

  void resume() {
    isolate.resume(isolate.pauseCapability);
  }
}

class _InitialServerMessage {
  String pipelineTypeName;
  Uri pipelineLibraryURI;
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;

  _InitialServerMessage(this.pipelineTypeName, this.pipelineLibraryURI,
      this.configuration, this.parentMessagePort);
}
