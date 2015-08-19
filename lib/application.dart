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

  /// Whether or not the server configuration defined by this instance can be shared across isolates.
  ///
  /// Defaults to false. When false, only one isolate may listen for requests on the [address] and [port]
  /// in this configuration. Otherwise, multiple isolates may. You should not need to set this flag directly,
  /// as starting an [Application] will determine if multiple isolates are being used.
  bool shared = false;

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
        this.shared = config.shared;
}

/// A abstract class that concrete subclasses will implement to provide request handling behavior.
///
/// [Application]s set up HTTP(s) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [ApplicationPipeline].
abstract class ApplicationPipeline {

  /// Allows an [ApplicationPipeline] to handle HTTP(s) requests from its [Application].
  ///
  /// Implementors of [ApplicationPipeline] must override this method to respond to an [Application]'s requests.
  /// Setting up listeners for tasks such as routing to resource controllers, logging utilities and authentication occur here.
  void attachTo(Stream<ResourceRequest> requestStream);
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

    configuration.shared = numberOfInstances > 1;

    for (int i = 0; i < numberOfInstances; i++) {
      var config =
          new ApplicationInstanceConfiguration.fromConfiguration(configuration);

      var serverRecord = await _spawn(config, i + 1);
      servers.add(serverRecord);
    }

    servers.forEach((i) {
      i.resume();
    });
  }

  Future<_ServerRecord> _spawn(ApplicationInstanceConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var pipelineTypeMirror = reflectType(pipelineType);
    var pipelineLibraryURI = (pipelineTypeMirror.owner as LibraryMirror).uri;
    var pipelineTypeName = MirrorSystem.getName(pipelineTypeMirror.simpleName);

    var initialMessage = new _InitialServerMessage(
        pipelineTypeName, pipelineLibraryURI, config, identifier, receivePort.sendPort);
    var isolate =
        await Isolate.spawn(_Server.entry, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new _ServerRecord(isolate, receivePort, identifier);
  }
}

class _Server {
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  HttpServer server;
  ApplicationPipeline pipeline;
  int identifier;

  _Server(this.pipeline, this.configuration, this.identifier, this.parentMessagePort);

  Future start() async {
    var onBind = (serv) {
      server = serv;

      server.serverHeader = "monadart/${this.identifier}";

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
        new _Server(app, params.configuration, params.identifier, params.parentMessagePort);

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
  int identifier;

  _InitialServerMessage(this.pipelineTypeName, this.pipelineLibraryURI,
      this.configuration, this.identifier, this.parentMessagePort);
}
