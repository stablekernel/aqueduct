import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../http/http.dart';
import '../utilities/resource_registry.dart';
import 'application_configuration.dart';
import 'application_server.dart';
import 'isolate_application_server.dart';
import 'isolate_supervisor.dart';

export 'application_configuration.dart';
export 'application_server.dart';

/// A container for web server applications.
///
/// Applications are responsible for managing starting and stopping of HTTP server instances across multiple isolates.
/// Behavior specific to an application is implemented by setting the [Application]'s [configuration] and providing
/// a [RequestSinkType].
///
/// Instances of this class are created by the command like `aqueduct serve` tool and rarely used by an Aqueduct developer directly.
class Application<RequestSinkType extends RequestSink> {
  Application();

  /// Used internally.
  List<ApplicationIsolateSupervisor> supervisors = [];

  /// The [ApplicationServer] managing delivering HTTP requests into this application.
  ///
  /// This property is only valid if this application is started with runOnMainIsolate set to true in [start].
  /// Tests may access this property to examine or directly use resources of a [RequestSink].
  ApplicationServer server;

  /// The [RequestSink] receiving requests on the main isolate.
  ///
  /// Applications run during testing are run on the main isolate. When running in this way,
  /// an application will only have one [RequestSinkType] receiving HTTP requests. This property is that instance.
  /// If an application is running across multiple isolates, this property is null. See [start] for more details.
  RequestSinkType get mainIsolateSink => server?.sink as RequestSinkType;

  /// A reference to a logger.
  ///
  /// This [Logger] will be named the same as the loggers used on each request sink.
  Logger logger = new Logger("aqueduct");

  /// The configuration for the HTTP server this application is running.
  ///
  /// This must be configured prior to [start]ing the [Application].
  ApplicationConfiguration configuration = new ApplicationConfiguration();

  /// Duration to wait for each isolate during startup before considered failure.
  ///
  /// Defaults to 30 seconds.
  Duration isolateStartupTimeout = new Duration(seconds: 30);

  /// Whether or not this application has finished [start] successfully.
  ///
  /// This will return true if [start] has been invoked and completed; i.e. this is the synchronous version of the [Future] returned by [start].
  ///
  /// This value will return to false after [stop] has completed.
  bool get hasFinishedLaunching => _interruptSubscription != null;

  StreamSubscription<ProcessSignal> _interruptSubscription;

  /// Starts the application by spawning Isolates that listen for HTTP requests.
  ///
  /// Returns a [Future] that completes when all [Isolate]s have started listening for requests.
  /// The [numberOfInstances] defines how many [Isolate]s are spawned running this application's [configuration]
  /// and [RequestSinkType].
  ///
  /// If this instances [RequestSinkType] implements `initializeApplication` (see [RequestSink] for more details),
  /// that one-time initialization method will be executed prior to the spawning of isolates and instantiations of [RequestSink].
  ///
  /// See also [test] for starting an application when running automated tests
  Future start({int numberOfInstances: 1, bool consoleLogging: false}) async {
    if (server != null || supervisors.length > 0) {
      throw new ApplicationStartupException("Application already started.");
    }

    if (configuration.address == null) {
      if (configuration.isIpv6Only) {
        configuration.address = InternetAddress.ANY_IP_V6;
      } else {
        configuration.address = InternetAddress.ANY_IP_V4;
      }
    }

    var requestSinkType = reflectClass(RequestSinkType);
    await _globalStart(requestSinkType, configuration);

    try {
      for (int i = 0; i < numberOfInstances; i++) {
        var supervisor = await _spawn(configuration, i + 1, logToConsole: consoleLogging);
        supervisors.add(supervisor);
        await supervisor.resume();
      }
    } catch (e, st) {
      logger.severe("$e", this, st);
      await stop().timeout(new Duration(seconds: 5));
      rethrow;
    }
    supervisors.forEach((sup) => sup.sendPendingMessages());

    _interruptSubscription = ProcessSignal.SIGINT.watch().listen((evt) {
      logger.info("Shutting down due to interrupt signal.");
      stop();
    });
  }

  /// Starts the application for the purpose of running automated tests.
  ///
  /// An application started in this way will run on the same isolate this method is invoked on. Use this method
  /// to start the application when running tests with the `test` package.
  Future test() async {
    if (server != null || supervisors.length > 0) {
      throw new ApplicationStartupException("Application already started.");
    }

    configuration.address = InternetAddress.LOOPBACK_IP_V4;

    var requestSinkType = reflectClass(RequestSinkType);
    await _globalStart(requestSinkType, configuration);

    try {
      var sink = requestSinkType.newInstance(new Symbol(""), [configuration]).reflectee;
      server = new ApplicationServer(configuration, 1, captureStack: true);

      await server.start(sink);
    } catch (e, st) {
      logger.severe("$e", this, st);
      await stop().timeout(new Duration(seconds: 5));
      throw new ApplicationStartupException(e);
    }

    _interruptSubscription = ProcessSignal.SIGINT.watch().listen((evt) {
      logger.info("Shutting down due to interrupt signal.");
      stop();
    });
  }

  /// Stops the application from running.
  ///
  /// Closes down every [RequestSinkType] and stops listening for HTTP requests.
  Future stop() async {
    await Future.wait(supervisors.map((s) => s.stop()));
    await server?.server?.close(force: true);

    await ServiceRegistry.defaultInstance.close();
    await _interruptSubscription?.cancel();

    _interruptSubscription = null;
    server = null;
    supervisors = [];

    logger.clearListeners();
  }

  static Future<APIDocument> document(
      Type sinkType, ApplicationConfiguration config, PackagePathResolver resolver) async {
    var sinkMirror = reflectClass(sinkType);

    config.isDocumenting = true;
    await _globalStart(sinkMirror, config);

    RequestSink sink = sinkMirror.newInstance(new Symbol(""), [config]).reflectee;
    sink.setupRouter(sink.router);
    sink.router.prepare();

    return sink.documentAPI(resolver);
  }

  static Future _globalStart(ClassMirror sinkType, ApplicationConfiguration config) {
    var globalStartSymbol = #initializeApplication;
    if (sinkType.staticMembers[globalStartSymbol] != null) {
      return sinkType.invoke(globalStartSymbol, [config]).reflectee;
    }

    return null;
  }

  Future<ApplicationIsolateSupervisor> _spawn(ApplicationConfiguration config, int identifier,
      {bool logToConsole: false}) async {
    var receivePort = new ReceivePort();

    var streamTypeMirror = reflectType(RequestSinkType);
    var streamLibraryURI = (streamTypeMirror.owner as LibraryMirror).uri;
    var streamTypeName = MirrorSystem.getName(streamTypeMirror.simpleName);

    var initialMessage = new ApplicationInitialServerMessage(
        streamTypeName, streamLibraryURI, config, identifier, receivePort.sendPort,
        logToConsole: logToConsole);
    var isolate = await Isolate.spawn(isolateServerEntryPoint, initialMessage, paused: true);

    return new ApplicationIsolateSupervisor(this, isolate, receivePort, identifier, logger,
        startupTimeout: isolateStartupTimeout);
  }
}

/// Thrown when an application encounters an exception during startup.
///
/// Contains the original exception that halted startup.
class ApplicationStartupException implements Exception {
  ApplicationStartupException(this.originalException);

  dynamic originalException;

  @override
  String toString() => originalException.toString();
}
