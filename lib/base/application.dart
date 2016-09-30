part of aqueduct;

/// A container for web server applications.
///
/// Applications are responsible for managing starting and stopping of HTTP server instances across multiple isolates.
/// Behavior specific to an application is implemented by setting the [Application]'s [configuration], and providing
/// a [SinkType].
class Application<SinkType extends RequestSink> {
  /// A list of items identifying the Isolates running a HTTP(s) listener and response handlers.
  ///
  /// This list will be populated based on the [numberOfInstances] passed in [start]. If [runOnMainIsolate] is true
  /// for [start], this list will be empty and [server] will be used instead.
  List<IsolateSupervisor> supervisors = [];

  /// The server this application is running when started on the main isolate.
  ///
  /// This value will be available to [Application]s that are [start]ed with [runOnMainIsolate]
  /// set to true and represents the only [_Server] this application is running.
  _Server server;

  /// A reference to a logger.
  ///
  /// This [Logger] will be named the same as the loggers used on each stream.
  Logger logger = new Logger("aqueduct");

  /// The configuration for the HTTP(s) server this application is running.
  ///
  /// This must be configured prior to [start]ing the [Application].
  ApplicationInstanceConfiguration configuration = new ApplicationInstanceConfiguration();

  /// Starts the application by spawning Isolates that listen for HTTP requests.
  ///
  /// Returns a [Future] that completes when all Isolates have started listening for requests.
  /// The [numberOfInstances] defines how many Isolates are spawned running this application's [configuration]
  /// and [SinkType]. If [runOnMainIsolate] is true (it defaults to false), the application will
  /// run a single instance of [SinkType] on the main isolate, ignoring [numberOfInstances].
  /// You should only [runOnMainIsolate] for testing purposes.
  Future start({int numberOfInstances: 1, bool runOnMainIsolate: false}) async {
    if (configuration.address == null) {
      if (configuration.isIpv6Only) {
        configuration.address = InternetAddress.ANY_IP_V6;
      } else {
        configuration.address = InternetAddress.ANY_IP_V4;
      }
    }

    if (runOnMainIsolate) {
      if (numberOfInstances > 1) {
        logger.info("runOnMainIsolate set to true, ignoring numberOfInstances (set to $numberOfInstances)");
      }

      var stream = reflectClass(SinkType).newInstance(new Symbol(""), [configuration.configurationOptions]).reflectee;
      server = new _Server(stream, configuration, 1);

      await server.start();
    } else {
      configuration._shared = true;

      supervisors = [];
      try {
        for (int i = 0; i < numberOfInstances; i ++) {
          var supervisor = await _spawn(configuration, i + 1);

          await supervisor.resume();

          supervisors.add(supervisor);
        }
      } catch (e, st) {
        await stop();
        logger.severe("$e", this, st);
        rethrow;
      }
    }
  }

  /// Stops the application from running.
  ///
  /// Closes down every stream (or [server] if started with [runOnMainIsolate]) and the associated servers.
  ///
  Future stop() async {
    await Future.wait(supervisors.map((s) => s.stop()));
    supervisors = [];

    await server?.server?.close(force: true);
  }

  APIDocument document(PackagePathResolver resolver) {
    RequestSink stream = reflectClass(SinkType).newInstance(new Symbol(""), [configuration.configurationOptions]).reflectee;
    stream.addRoutes();
    stream.router.finalize();

    return stream.documentAPI(resolver);
  }

  Future<IsolateSupervisor> _spawn(ApplicationInstanceConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var streamTypeMirror = reflectType(SinkType);
    var streamLibraryURI = (streamTypeMirror.owner as LibraryMirror).uri;
    var streamTypeName = MirrorSystem.getName(streamTypeMirror.simpleName);

    var initialMessage = new InitialServerMessage(streamTypeName, streamLibraryURI, config, identifier, receivePort.sendPort);
    var isolate = await Isolate.spawn(isolateServerEntryPoint, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new IsolateSupervisor(this, isolate, receivePort, identifier, logger);
  }

  Future isolateDidExitWithError(IsolateSupervisor supervisor, String errorMessage, StackTrace stackTrace) async {
    logger.severe("Restarting terminated isolate. Exit reason $errorMessage", supervisor, stackTrace);

    var identifier = supervisor.identifier;
    supervisors.remove(supervisor);
    try {
      var supervisor = await _spawn(configuration, identifier);
      await supervisor.resume();
      supervisors.add(supervisor);
    } catch (e, st) {
      await stop();
      logger.severe("$e", supervisor, st);
    }
  }
}

class InitialServerMessage {
  String streamTypeName;
  Uri streamLibraryURI;
  ApplicationInstanceConfiguration configuration;
  SendPort parentMessagePort;
  int identifier;

  InitialServerMessage(this.streamTypeName, this.streamLibraryURI, this.configuration, this.identifier, this.parentMessagePort);
}
