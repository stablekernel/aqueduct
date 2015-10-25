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

  /// The name of the server-side HTTPS certificate.
  ///
  /// Defaults to null. If this is null and [isUsingClientCertificate] is false, the server will
  /// run over HTTP instead of HTTPs.
  String serverCertificateName = null;

  /// Options for instances of ApplicationPipeline to use when in this application.
  ///
  /// Allows delivery of custom configuration parameters to ApplicationPipeline instances
  /// that are attached to this application.
  Map<dynamic, dynamic> pipelineOptions;

  bool _shared = false;

  /// The default constructor.
  ApplicationInstanceConfiguration();

  /// A copy constructor
  ApplicationInstanceConfiguration.fromConfiguration(
      ApplicationInstanceConfiguration config)
      : this.address = config.address,
        this.port = config.port,
        this.isIpv6Only = config.isIpv6Only,
        this.isUsingClientCertificate = config.isUsingClientCertificate,
        this.serverCertificateName = config.serverCertificateName,
        this._shared = config._shared,
        this.pipelineOptions = config.pipelineOptions;
}

/// A abstract class that concrete subclasses will implement to provide request handling behavior.
///
/// [Application]s set up HTTP(s) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [ApplicationPipeline]. Instances of this class must implement the
/// [handleRequest] method from [RequestHandler] - this is the entry point of all requests into this pipeline.
abstract class ApplicationPipeline extends RequestHandler {
  /// Passed in options for this pipeline from its owning [Application].
  ///
  /// These values give an opportunity for a pipeline to have a customization point within attachTo., like running
  /// the owning [Application] in 'Development' or 'Production' mode. This property will always be set prior to invoking attachTo, but may be null
  /// if the user did not set any configuration values.
  Map<String, dynamic> options;

  RequestHandler initialHandler();

  Future willOpen() { return null; }

  void didOpen() {}

  Future willReceiveRequest(ResourceRequest request) { return null; }
}

/// A container for web server applications.
///
/// Applications are responsible for managing starting and stopping of HTTP server instances across multiple isolates.
/// Behavior specific to an application is implemented by setting the [Application]'s [configuration] and providing
/// a [pipelineType] as a [ApplicationPipeline] subclass.
class Application {
  /// A list of items identifying the Isolates running a HTTP(s) listener and response handlers.
  List<_ServerRecord> servers = [];

  /// The configuration for the HTTP(s) server this application is running.
  ///
  /// This must be configured prior to [start]ing the [Application].
  ApplicationInstanceConfiguration configuration =
      new ApplicationInstanceConfiguration();

  /// The type of [ApplicationPipeline] that configures how requests are handled.
  ///
  /// This must be configured prior to [start]ing the [Application]. Must be a subtype of [ApplicationPipeline].
  Type pipelineType;

  /// Starts the application by spawning Isolates that listen for HTTP(s) requests.
  ///
  /// Returns a [Future] that completes when all Isolates have started listening for requests.
  /// The [numberOfInstances] defines how many Isolates are spawned running this application's [configuration]
  /// and [pipelineType].
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
      var config =
          new ApplicationInstanceConfiguration.fromConfiguration(configuration);

      var serverRecord = await _spawn(config, i + 1);
      servers.add(serverRecord);
    }

    var futures = servers.map((i) {
      return i.resume();
    });

    await Future.wait(futures);
  }

  Future<_ServerRecord> _spawn(
      ApplicationInstanceConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var pipelineTypeMirror = reflectType(pipelineType);
    var pipelineLibraryURI = (pipelineTypeMirror.owner as LibraryMirror).uri;
    var pipelineTypeName = MirrorSystem.getName(pipelineTypeMirror.simpleName);

    var initialMessage = new _InitialServerMessage(pipelineTypeName,
        pipelineLibraryURI, config, identifier, receivePort.sendPort);
    var isolate =
        await Isolate.spawn(_Server.entry, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new _ServerRecord(isolate, receivePort, identifier);
  }
}

class _Server {
  static String _FinishedMessage = "finished";

  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  HttpServer server;
  ApplicationPipeline pipeline;
  int identifier;

  _Server(this.pipeline, this.configuration, this.identifier,
      this.parentMessagePort);

  Future start() async {
    pipeline.options = configuration.pipelineOptions;
    await pipeline.willOpen();

    pipeline.next = pipeline.initialHandler();

    var onBind = (s) {
      server = s;

      server.serverHeader = "monadart/${this.identifier}";

      server.map((httpReq) => new ResourceRequest(httpReq)).listen((req) async {
        await pipeline.willReceiveRequest(req);
        pipeline.deliver(req);
      });

      pipeline.didOpen();

      parentMessagePort.send(_FinishedMessage);
    };

    if (configuration.serverCertificateName != null) {
      HttpServer
          .bindSecure(configuration.address, configuration.port,
              certificateName: configuration.serverCertificateName,
              v6Only: configuration.isIpv6Only,
              shared: configuration._shared)
          .then(onBind);
    } else if (configuration.isUsingClientCertificate) {
      HttpServer
          .bindSecure(configuration.address, configuration.port,
              requestClientCertificate: true,
              v6Only: configuration.isIpv6Only,
              shared: configuration._shared)
          .then(onBind);
    } else {
      HttpServer
          .bind(configuration.address, configuration.port,
              v6Only: configuration.isIpv6Only, shared: configuration._shared)
          .then(onBind);
    }
  }

  static void entry(_InitialServerMessage params) {
    var pipelineSourceLibraryMirror =
        currentMirrorSystem().libraries[params.pipelineLibraryURI];
    var pipelineTypeMirror = pipelineSourceLibraryMirror.declarations[
        new Symbol(params.pipelineTypeName)] as ClassMirror;

    var app = pipelineTypeMirror.newInstance(new Symbol(""), []).reflectee;
    var server = new _Server(
        app, params.configuration, params.identifier, params.parentMessagePort);

    server.start();
  }
}

class _ServerRecord {
  final Isolate isolate;
  final ReceivePort receivePort;
  final int identifier;

  _ServerRecord(this.isolate, this.receivePort, this.identifier);

  Future resume() {
    var completer = new Completer();
    receivePort.listen((msg) {
      if (msg == _Server._FinishedMessage) {
        completer.complete();
      }
    });
    isolate.resume(isolate.pauseCapability);
    return completer.future.timeout(new Duration(seconds: 30));
  }
}

class _InitialServerMessage {
  String pipelineTypeName;
  Uri pipelineLibraryURI;
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;

  _InitialServerMessage(this.pipelineTypeName, this.pipelineLibraryURI,
      this.configuration, this.identifier, this.parentMessagePort);
}
