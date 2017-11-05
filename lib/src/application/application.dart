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
/// An application implements does not implement any request handling logic. Instead, it instantiates instances of [T]
/// that have a [ApplicationChannel.entryPoint] that HTTP requests are sent to to be handled.
///
/// Instances of this class are created by the command like `aqueduct serve` tool and rarely used by an Aqueduct developer directly.
class Application<T extends ApplicationChannel> {
  /// Isolate supervisors for application started with [start].
  ///
  /// Each spawned isolated is managed by the instances in this property.
  List<ApplicationIsolateSupervisor> supervisors = [];

  /// The [ApplicationServer] managing delivering HTTP requests into this application.
  ///
  /// This property is only valid if this application is started with runOnMainIsolate set to true in [start].
  /// Tests may access this property to examine or directly use resources of a [ApplicationChannel].
  ApplicationServer server;

  /// The [ApplicationChannel] when running via [test].
  ///
  /// Applications run during testing are run on the main isolate. When running in this way,
  /// an application will only have one [T] receiving HTTP requests. This property is that instance.
  /// If an application is running across multiple isolates, this property is null. See [start] for more details.
  T get channel => server?.channel as T;

  /// A reference to a logger.
  ///
  /// This [Logger] will be named the same as the loggers used on each channel.
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
  /// The [numberOfInstances] defines how many [Isolate]s are spawned.
  ///
  /// Each isolate creates a channel defined by [T]'s [ApplicationChannel.entryPoint] that requests are sent to.
  ///
  /// If [T] implements `initializeApplication` (see [ApplicationChannel] for more details),
  /// that one-time initialization method will be executed prior to the spawning of isolates and instantiations of [ApplicationChannel].
  ///
  /// See also [test] for starting an application when running automated tests.
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

    var channelType = reflectClass(T);
    try {
      await _globalStart(channelType, configuration);

      for (int i = 0; i < numberOfInstances; i++) {
        var supervisor = await _spawn(channelType, configuration, i + 1, logToConsole: consoleLogging);
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
  /// to start the application when running tests with the `aqueduct/aqueduct_test` library.
  Future test() async {
    if (server != null || supervisors.length > 0) {
      throw new ApplicationStartupException("Application already started.");
    }

    configuration.address = InternetAddress.LOOPBACK_IP_V4;

    var channelType = reflectClass(T);
    try {
      await _globalStart(channelType, configuration);

      server = new ApplicationServer(channelType, configuration, 1, captureStack: true);

      await server.start();
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
  /// Closes down every channel and stops listening for HTTP requests.
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

  /// Creates an [APIDocument] for this application.
  static Future<APIDocument> document(
      Type channelType, ApplicationConfiguration config, PackagePathResolver resolver) async {
    var channelMirror = reflectClass(channelType);

    config.isDocumenting = true;
    await _globalStart(channelMirror, config);

    final server = new ApplicationServer(channelMirror, config, 1, captureStack: true);

    await server.channel.prepare();

    return server.channel.documentAPI(resolver);
  }

  static Future _globalStart(ClassMirror channelType, ApplicationConfiguration config) {
    var globalStartSymbol = #initializeApplication;
    if (channelType.staticMembers[globalStartSymbol] != null) {
      return channelType.invoke(globalStartSymbol, [config]).reflectee;
    }

    return null;
  }

  Future<ApplicationIsolateSupervisor> _spawn(ClassMirror channelTypeMirror, ApplicationConfiguration config, int identifier,
      {bool logToConsole: false}) async {
    var receivePort = new ReceivePort();

    var streamLibraryURI = (channelTypeMirror.owner as LibraryMirror).uri;
    var streamTypeName = MirrorSystem.getName(channelTypeMirror.simpleName);

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
