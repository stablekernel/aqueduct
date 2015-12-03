part of monadart;

/// A set of values to configure an instance of a web server application.
class ApplicationInstanceConfiguration {
  /// The address to listen for HTTP requests on.
  ///
  /// By default, this address will default to 'any' address. If [isIpv6Only] is true,
  /// the address will be any IPv6 address, otherwise, it will be any IPv4 address.
  dynamic address;

  /// The port to listen for HTTP requests on.
  ///
  /// Defaults to 8080.
  int port = 8080;

  /// Whether or not the application should only listen for IPv6 requests.
  ///
  /// Defaults to false. This flag impacts the [address] property if it has not been set.
  bool isIpv6Only = false;

  /// Whether or not the application's request handlers should use client-side HTTPS certificates.
  ///
  /// Defaults to false. If this is false and [serverCertificateName] is null, the server will
  /// run over HTTP instead of HTTPS.
  bool isUsingClientCertificate = false;

  /// Information for securing the application over HTTPS.
  ///
  /// Defaults to null. If this is null, this application will run unsecured over HTTP. To
  /// run securely over HTTPS, this property must be set with valid security details.
  SecurityContext securityContext = null;

  /// Options for instances of ApplicationPipeline to use when in this application.
  ///
  /// Allows delivery of custom configuration parameters to ApplicationPipeline instances
  /// that are attached to this application.
  Map<dynamic, dynamic> pipelineOptions;

  bool _shared = false;
}


/// A container for web server applications.
///
/// Applications are responsible for managing starting and stopping of HTTP server instances across multiple isolates.
/// Behavior specific to an application is implemented by setting the [Application]'s [configuration], and providing
/// a [PipelineType] and [RequestType].
class Application<PipelineType extends ApplicationPipeline> {
  /// A list of items identifying the Isolates running a HTTP(s) listener and response handlers.
  List<_ServerSupervisor> servers = [];

  /// The configuration for the HTTP(s) server this application is running.
  ///
  /// This must be configured prior to [start]ing the [Application].
  ApplicationInstanceConfiguration configuration = new ApplicationInstanceConfiguration();

  /// Starts the application by spawning Isolates that listen for HTTP(s) requests.
  ///
  /// Returns a [Future] that completes when all Isolates have started listening for requests.
  /// The [numberOfInstances] defines how many Isolates are spawned running this application's [configuration]
  /// and [PipelineType].
  Future start({int numberOfInstances: 1}) async {
    if (configuration.address == null) {
      if (configuration.isIpv6Only) {
        configuration.address = InternetAddress.ANY_IP_V6;
      } else {
        configuration.address = InternetAddress.ANY_IP_V4;
      }
    }

    configuration._shared = numberOfInstances > 1;

    for (int i = 0; i < numberOfInstances; i++) {
      var serverRecord = await _spawn(configuration, i + 1);
      servers.add(serverRecord);
    }

    var futures = servers.map((i) {
      return i.resume();
    });

    await Future.wait(futures);
  }

  Future stop() async {
    await Future.wait(servers.map((s) => s.stop()));
    servers = [];
  }

  Future<_ServerSupervisor> _spawn(ApplicationInstanceConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var pipelineTypeMirror = reflectType(PipelineType);
    var pipelineLibraryURI = (pipelineTypeMirror.owner as LibraryMirror).uri;
    var pipelineTypeName = MirrorSystem.getName(pipelineTypeMirror.simpleName);

    var initialMessage = new _InitialServerMessage(pipelineTypeName, pipelineLibraryURI, config, identifier, receivePort.sendPort);
    var isolate = await Isolate.spawn(_Server.entry, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new _ServerSupervisor(isolate, receivePort, identifier);
  }
}

class _Server {
  ApplicationInstanceConfiguration configuration;
  SendPort supervisingApplicationPort;
  ReceivePort supervisingReceivePort;
  HttpServer server;
  ApplicationPipeline pipeline;
  int identifier;

  _Server(this.pipeline, this.configuration, this.identifier, this.supervisingApplicationPort) {
    supervisingReceivePort = new ReceivePort();
    supervisingReceivePort.listen(listener);
  }

  ResourceRequest createRequest(HttpRequest req) {
    return new ResourceRequest(req);
  }

  Future start() async {
    pipeline.addRoutes();
    pipeline.nextHandler = pipeline.initialHandler();

    var onBind = (s) async {
      new Logger("monadart").info("Server monadart/$identifier started.");

      server = s;

      server.serverHeader = "monadart/${this.identifier}";

      await pipeline.willOpen();

      server.map(createRequest).listen((ResourceRequest req) async {
        new Logger("monadart").info("Request received $req.");
        await pipeline.willReceiveRequest(req);
        pipeline.deliver(req);
      });

      pipeline.didOpen();

      supervisingApplicationPort.send(supervisingReceivePort.sendPort);
    };

    if (configuration.securityContext != null) {
      HttpServer
          .bindSecure(configuration.address, configuration.port, configuration.securityContext,
              requestClientCertificate: configuration.isUsingClientCertificate, v6Only: configuration.isIpv6Only, shared: configuration._shared)
          .then(onBind);
    } else {
      HttpServer.bind(configuration.address, configuration.port, v6Only: configuration.isIpv6Only, shared: configuration._shared).then(onBind);
    }
  }

  void listener(dynamic message) {
    if (message == _ServerSupervisor._MessageStop) {
      server.close().then((s) {
        supervisingApplicationPort.send(_ServerSupervisor._MessageStop);
      });
    }
  }

  static void entry(_InitialServerMessage params) {
    var pipelineSourceLibraryMirror = currentMirrorSystem().libraries[params.pipelineLibraryURI];
    var pipelineTypeMirror = pipelineSourceLibraryMirror.declarations[new Symbol(params.pipelineTypeName)] as ClassMirror;

    var app = pipelineTypeMirror.newInstance(new Symbol(""), [params.configuration.pipelineOptions]).reflectee;
    var server = new _Server(app, params.configuration, params.identifier, params.parentMessagePort);

    server.start();
  }
}

class _ServerSupervisor {
  static String _MessageStop = "_MessageStop";

  final Isolate isolate;
  final ReceivePort receivePort;
  final int identifier;

  SendPort _serverSendPort;

  Completer _launchCompleter;
  Completer _stopCompleter;

  _ServerSupervisor(this.isolate, this.receivePort, this.identifier) {
  }

  Future resume() {
    _launchCompleter = new Completer();
    receivePort.listen(listener);

    isolate.resume(isolate.pauseCapability);
    return _launchCompleter.future.timeout(new Duration(seconds: 30));
  }

  Future stop() {
    _stopCompleter = new Completer();
    _serverSendPort.send(_MessageStop);
    return _stopCompleter.future.timeout(new Duration(seconds: 30));
  }

  void listener(dynamic message) {
    if (message is SendPort) {
      _launchCompleter.complete();
      _launchCompleter = null;

      _serverSendPort = message;
    } else if (message == _MessageStop) {
      _stopCompleter.complete();
      _stopCompleter = null;
    }
  }
}

class _InitialServerMessage {
  String pipelineTypeName;
  Uri pipelineLibraryURI;
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;

  _InitialServerMessage(this.pipelineTypeName, this.pipelineLibraryURI, this.configuration, this.identifier, this.parentMessagePort);
}
