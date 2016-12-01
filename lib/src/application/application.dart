import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../http/http.dart';
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
class Application<RequestSinkType extends RequestSink> {
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

  /// Starts the application by spawning Isolates that listen for HTTP requests.
  ///
  /// Returns a [Future] that completes when all [Isolate]s have started listening for requests.
  /// The [numberOfInstances] defines how many [Isolate]s are spawned running this application's [configuration]
  /// and [RequestSinkType]. If [runOnMainIsolate] is true (it defaults to false), the application will
  /// run a single instance of [RequestSinkType] on the main isolate, ignoring [numberOfInstances]. Additionally,
  /// the server will only listen on localhost, regardless of any specified address. You should only [runOnMainIsolate] for testing purposes.
  Future start({int numberOfInstances: 1, bool runOnMainIsolate: false}) async {
    if (configuration.address == null) {
      if (runOnMainIsolate) {
        configuration.address = InternetAddress.LOOPBACK_IP_V4;
      } else {
        if (configuration.isIpv6Only) {
          configuration.address = InternetAddress.ANY_IP_V6;
        } else {
          configuration.address = InternetAddress.ANY_IP_V4;
        }
      }
    }

    if (runOnMainIsolate) {
      if (numberOfInstances > 1) {
        logger.info(
            "runOnMainIsolate set to true, ignoring numberOfInstances (set to $numberOfInstances)");
      }

      var sink = reflectClass(RequestSinkType).newInstance(
          new Symbol(""), [configuration.configurationOptions]).reflectee;
      server = new ApplicationServer(sink, configuration, 1);

      await server.start();
    } else {
      supervisors = [];
      try {
        for (int i = 0; i < numberOfInstances; i++) {
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
  /// Closes down every [RequestSinkType] and stops listening for HTTP requests.
  Future stop() async {
    await Future.wait(supervisors.map((s) => s.stop()));
    supervisors = [];

    await server?.server?.close(force: true);
  }

  APIDocument document(PackagePathResolver resolver) {
    RequestSink sink = reflectClass(RequestSinkType).newInstance(
        new Symbol(""), [configuration.configurationOptions]).reflectee;
    sink.setupRouter(sink.router);
    sink.router.finalize();

    return sink.documentAPI(resolver);
  }

  Future<ApplicationIsolateSupervisor> _spawn(
      ApplicationConfiguration config, int identifier) async {
    var receivePort = new ReceivePort();

    var streamTypeMirror = reflectType(RequestSinkType);
    var streamLibraryURI = (streamTypeMirror.owner as LibraryMirror).uri;
    var streamTypeName = MirrorSystem.getName(streamTypeMirror.simpleName);

    var initialMessage = new ApplicationInitialServerMessage(streamTypeName,
        streamLibraryURI, config, identifier, receivePort.sendPort);
    var isolate = await Isolate.spawn(isolateServerEntryPoint, initialMessage,
        paused: true);
    isolate.addErrorListener(receivePort.sendPort);

    return new ApplicationIsolateSupervisor(
        this, isolate, receivePort, identifier, logger);
  }

  /// Used internally.
  Future isolateDidExitWithError(ApplicationIsolateSupervisor supervisor,
      String errorMessage, StackTrace stackTrace) async {
    logger.severe("Restarting terminated isolate. Exit reason $errorMessage",
        supervisor, stackTrace);

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

/// Thrown when an application encounters an exception during startup.
///
/// Contains the original exception that halted startup.
class ApplicationStartupException implements Exception {
  ApplicationStartupException(this.originalException);

  dynamic originalException;

  String toString() => originalException.toString();
}

/// An exception originating from an [Isolate] within an [Application].
@Deprecated(
    "This class will become private in 1.1. Use ApplicationStartupException in its place.")
class ApplicationSupervisorException implements Exception {
  ApplicationSupervisorException(this.message);

  final String message;

  String toString() {
    return "$message";
  }
}
