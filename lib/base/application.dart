part of monadart;

/// A container for web server applications.
///
/// Applications are responsible for managing starting and stopping of HTTP server instances across multiple isolates.
/// Behavior specific to an application is implemented by setting the [Application]'s [configuration], and providing
/// a [PipelineType] and [RequestType].
class Application<PipelineType extends ApplicationPipeline> {
  /// A list of items identifying the Isolates running a HTTP(s) listener and response handlers.
  ///
  /// This list will be populated based on the [numberOfInstances] passed in [start]. If [runOnMainIsolate] is true
  /// for [start], this list will be empty and [server] will be populated.
  List<IsolateSupervisor> supervisors = [];

  /// The server this application is running when started on the main isolate.
  ///
  /// This value will be available to [Application]s that are [start]ed with [runOnMainIsolate]
  /// set to true and represents the only [Server] this application is running.
  Server server;

  /// The configuration for the HTTP(s) server this application is running.
  ///
  /// This must be configured prior to [start]ing the [Application].
  ApplicationInstanceConfiguration configuration = new ApplicationInstanceConfiguration();

  /// Starts the application by spawning Isolates that listen for HTTP(s) requests.
  ///
  /// Returns a [Future] that completes when all Isolates have started listening for requests.
  /// The [numberOfInstances] defines how many Isolates are spawned running this application's [configuration]
  /// and [PipelineType]. If [runOnMainIsolate] is true (it defaults to false), the application will
  /// run a single instance of [PipelineType] on the main isolate, ignorning [numberOfInstances].
  /// You should only use this configuration for testing purposes.
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
        print("runOnMainIsolate set to true, ignoring numberOfInstances (set to $numberOfInstances)");
      }

      var pipeline = reflectClass(PipelineType).newInstance(new Symbol(""), [configuration.pipelineOptions]).reflectee;
      server = new Server(pipeline, configuration, 1);

      await server.start();
    } else {
      configuration._shared = numberOfInstances > 1;

      supervisors = [];
      try {
        for (int i = 0; i < numberOfInstances; i++) {
          var supervisor = await _spawn(configuration, i + 1);

          await supervisor.resume();

          supervisors.add(supervisor);
        }
      } catch (e) {
        await stop();
      }
    }
  }

  /// Stops the application from running.
  ///
  /// Closes down every pipeline (or [server] if started with [runOnMainIsolate]) and the associated servers.
  ///
  Future stop() async {
    await Future.wait(supervisors.map((s) => s.stop()));
    supervisors = [];

    server?.server?.close();
  }

  Future<IsolateSupervisor> _spawn(ApplicationInstanceConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var pipelineTypeMirror = reflectType(PipelineType);
    var pipelineLibraryURI = (pipelineTypeMirror.owner as LibraryMirror).uri;
    var pipelineTypeName = MirrorSystem.getName(pipelineTypeMirror.simpleName);

    var initialMessage = new _InitialServerMessage(pipelineTypeName, pipelineLibraryURI, config, identifier, receivePort.sendPort);
    var isolate = await Isolate.spawn(IsolateServer.entry, initialMessage, paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new IsolateSupervisor(isolate, receivePort, identifier);
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
