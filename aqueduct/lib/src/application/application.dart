import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:logging/logging.dart';

import '../http/http.dart';
import 'application_server.dart';
import 'isolate_application_server.dart';
import 'isolate_supervisor.dart';
import 'options.dart';
import 'service_registry.dart';

export 'application_server.dart';
export 'options.dart';
export 'service_registry.dart';

/// This object starts and stops instances of your [ApplicationChannel].
///
/// An application object opens HTTP listeners that forward requests to instances of your [ApplicationChannel].
/// It is unlikely that you need to use this class directly - the `aqueduct serve` command creates an application object
/// on your behalf.
class Application<T extends ApplicationChannel> {
  /// A list of isolates that this application supervises.
  List<ApplicationIsolateSupervisor> supervisors = [];

  /// The [ApplicationServer] listening for HTTP requests while under test.
  ///
  /// This property is only valid when an application is started via [test].
  ApplicationServer server;

  /// The [ApplicationChannel] handling requests while under test.
  ///
  /// This property is only valid when an application is started via [test]. You use
  /// this value to access elements of your application channel during testing.
  T get channel => server?.channel as T;

  /// The logger that this application will write messages to.
  ///
  /// This logger's name will appear as 'aqueduct'.
  Logger logger = new Logger("aqueduct");

  /// The options used to configure this application.
  ///
  /// Changing these values once the application has started will have no effect.
  ApplicationOptions options = new ApplicationOptions();

  /// The duration to wait for each isolate during startup before failing.
  ///
  /// A [TimeoutException] is thrown if an isolate fails to startup in this time period.
  ///
  /// Defaults to 30 seconds.
  Duration isolateStartupTimeout = new Duration(seconds: 30);

  /// Whether or not this application is running.
  ///
  /// This will return true if [start]/[test] have been invoked and completed; i.e. this is the synchronous version of the [Future] returned by [start]/[test].
  ///
  /// This value will return to false after [stop] has completed.
  bool get isRunning => _hasFinishedLaunching;
  bool _hasFinishedLaunching = false;

  /// Starts this application, allowing it to handle HTTP requests.
  ///
  /// This method spawns [numberOfInstances] isolates, instantiates your application channel
  /// for each of these isolates, and opens an HTTP listener that sends requests to these instances.
  ///
  /// The [Future] returned from this method will complete once all isolates have successfully started
  /// and are available to handle requests.
  ///
  /// If your application channel implements [ApplicationChannel.initializeApplication],
  /// it will be invoked prior to any isolate being spawned.
  ///
  /// See also [test] for starting an application when running automated tests.
  Future start({int numberOfInstances: 1, bool consoleLogging: false}) async {
    if (server != null || supervisors.length > 0) {
      throw new StateError("Application error. Cannot invoke 'start' on already running Aqueduct application.");
    }

    if (options.address == null) {
      if (options.isIpv6Only) {
        options.address = InternetAddress.anyIPv6;
      } else {
        options.address = InternetAddress.anyIPv4;
      }
    }

    var channelType = reflectClass(T);
    try {
      await _globalStart(channelType, options);

      for (int i = 0; i < numberOfInstances; i++) {
        var supervisor = await _spawn(channelType, options, i + 1, logToConsole: consoleLogging);
        supervisors.add(supervisor);
        await supervisor.resume();
      }
    } catch (e, st) {
      logger.severe("$e", this, st);
      await stop().timeout(new Duration(seconds: 5));
      rethrow;
    }
    supervisors.forEach((sup) => sup.sendPendingMessages());
    _hasFinishedLaunching = true;
  }

  /// Starts the application for the purpose of running automated tests.
  ///
  /// An application started in this way will run on the same isolate this method is invoked on. Use this method
  /// to start the application when running tests with the `aqueduct_test` library.
  Future test() async {
    if (server != null || supervisors.length > 0) {
      throw new StateError("Application error. Cannot invoke 'test' on already running Aqueduct application.");
    }

    options.address = InternetAddress.loopbackIPv4;

    var channelType = reflectClass(T);
    try {
      await _globalStart(channelType, options);

      server = new ApplicationServer(channelType, options, 1, captureStack: true);

      await server.start();
      _hasFinishedLaunching = true;
    } catch (e, st) {
      logger.severe("$e", this, st);
      await stop().timeout(new Duration(seconds: 5));
      rethrow;
    }
  }

  /// Stops the application from running.
  ///
  /// Closes every isolate and their channel and stops listening for HTTP requests.
  /// The [ApplicationServiceRegistry] will close any of its resources.
  Future stop() async {
    _hasFinishedLaunching = false;
    await Future.wait(supervisors.map((s) => s.stop()));
    await server?.server?.close(force: true);

    await ApplicationServiceRegistry.defaultInstance.close();
    _hasFinishedLaunching = false;
    server = null;
    supervisors = [];

    logger.clearListeners();
  }

  /// Creates an [APIDocument] from an [ApplicationChannel].
  ///
  /// [channelType] must be a subclass [ApplicationChannel]. This method is called by the `aqueduct document` CLI.
  static Future<APIDocument> document(Type channelType, ApplicationOptions config, Map<String, dynamic> projectSpec) async {
    var channelMirror = reflectClass(channelType);

    await _globalStart(channelMirror, config);

    final server = new ApplicationServer(channelMirror, config, 1, captureStack: true);

    await server.channel.prepare();

    final doc = await server.channel.documentAPI(projectSpec);

    await server.channel.close();

    return doc;
  }

  static Future _globalStart(ClassMirror channelType, ApplicationOptions config) {
    var globalStartSymbol = #initializeApplication;
    if (channelType.staticMembers[globalStartSymbol] != null) {
      return channelType.invoke(globalStartSymbol, [config]).reflectee;
    }

    return null;
  }

  Future<ApplicationIsolateSupervisor> _spawn(ClassMirror channelTypeMirror, ApplicationOptions config, int identifier,
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
