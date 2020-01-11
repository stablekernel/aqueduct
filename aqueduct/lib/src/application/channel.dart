import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/application/service_registry.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:runtime/runtime.dart';

import '../http/http.dart';
import 'application.dart';
import 'isolate_application_server.dart';

/// An object that defines the behavior specific to your application.
///
/// You create a subclass of [ApplicationChannel] to initialize your application's services and define how HTTP requests are handled by your application.
/// There *must* only be one subclass in an application and it must be visible to your application library file, e.g., 'package:my_app/my_app.dart'.
///
/// You must implement [entryPoint] to define the controllers that comprise your application channel. Most applications will
/// also override [prepare] to read configuration values and initialize services. Some applications will provide an [initializeApplication]
/// method to do global startup tasks.
///
/// When your application is started, an instance of your application channel is created for each isolate (see [Application.start]). Each instance
/// is a replica of your application that runs in its own memory isolated thread.
abstract class ApplicationChannel implements APIComponentDocumenter {
  /// You implement this method to provide global initialization for your application.
  ///
  /// Most of your application initialization code is written in [prepare], which is invoked for each isolate. For initialization that
  /// needs to occur once per application start, you must provide an implementation for this method. This method is invoked prior
  /// to any isolates being spawned.
  ///
  /// You may alter [options] in this method and those changes will be available in each instance's [options]. To pass arbitrary data
  /// to each of your isolates at startup, add that data to [ApplicationOptions.context].
  ///
  /// Example:
  ///
  ///         class MyChannel extends ApplicationChannel {
  ///           static Future initializeApplication(ApplicationOptions options) async {
  ///             options.context["runtimeOption"] = "foo";
  ///           }
  ///
  ///           Future prepare() async {
  ///             if (options.context["runtimeOption"] == "foo") {
  ///               // do something
  ///             }
  ///           }
  ///         }
  ///
  ///
  /// Do not configure objects like [CodecRegistry], [CORSPolicy.defaultPolicy] or any other value that isn't explicitly passed through [options].
  ///
  /// * Note that static methods are not inherited in Dart and therefore you are not overriding this method. The declaration of this method in the base [ApplicationChannel] class
  /// is for documentation purposes.
  static Future initializeApplication(ApplicationOptions options) async {}

  /// The logger that this object will write messages to.
  ///
  /// This logger's name appears as 'aqueduct'.
  Logger get logger => Logger("aqueduct");

  /// The [ApplicationServer] that sends HTTP requests to this object.
  ApplicationServer get server => _server;

  set server(ApplicationServer server) {
    _server = server;
    messageHub._outboundController.stream.listen(server.sendApplicationEvent);
    server.hubSink = messageHub._inboundController.sink;
  }

  /// Use this object to send data to channels running on other isolates.
  ///
  /// You use this object to synchronize state across the isolates of an application. Any data sent
  /// through this object will be received by every other channel in your application (except the one that sent it).
  final ApplicationMessageHub messageHub = ApplicationMessageHub();

  /// The context used for setting up HTTPS in an application.
  ///
  /// If this value is non-null, the [server] receiving HTTP requests will only accept requests over HTTPS.
  ///
  /// By default, this value is null. If the [ApplicationOptions] provided to the application are configured to
  /// reference a private key and certificate file, this value is derived from that information. You may override
  /// this method to provide an alternative means to creating a [SecurityContext].
  SecurityContext get securityContext {
    if (options?.certificateFilePath == null ||
        options?.privateKeyFilePath == null) {
      return null;
    }

    return SecurityContext()
      ..useCertificateChain(options.certificateFilePath)
      ..usePrivateKey(options.privateKeyFilePath);
  }

  /// The configuration options used to start the application this channel belongs to.
  ///
  /// These options are set when starting the application. Changes to this object have no effect
  /// on other isolates.
  ApplicationOptions options;

  /// You implement this accessor to define how HTTP requests are handled by your application.
  ///
  /// You must implement this method to return the first controller that will handle an HTTP request. Additional controllers
  /// are linked to the first controller to create the entire flow of your application's request handling logic. This method
  /// is invoked during startup and controllers cannot be changed after it is invoked. This method is always invoked after
  /// [prepare].
  ///
  /// In most applications, the first controller is a [Router]. Example:
  ///
  ///         @override
  ///         Controller get entryPoint {
  ///           final router = Router();
  ///           router.route("/path").link(() => PathController());
  ///           return router;
  ///         }
  Controller get entryPoint;

  ApplicationServer _server;

  /// You override this method to perform initialization tasks.
  ///
  /// This method allows this instance to perform any initialization (other than setting up the [entryPoint]). This method
  /// is often used to set up services that [Controller]s use to fulfill their duties. This method is invoked
  /// prior to [entryPoint], so that the services it creates can be injected into [Controller]s.
  ///
  /// By default, this method does nothing.
  Future prepare() async {}

  /// You override this method to perform initialization tasks that occur after [entryPoint] has been established.
  ///
  /// Override this method to take action just before [entryPoint] starts receiving requests. By default, does nothing.
  void willStartReceivingRequests() {}

  /// You override this method to release any resources created in [prepare].
  ///
  /// This method is invoked when the owning [Application] is stopped. It closes open ports
  /// that this channel was using so that the application can be properly shut down.
  ///
  /// Prefer to use [ServiceRegistry] instead of overriding this method.
  ///
  /// If you do override this method, you must call the super implementation.
  @mustCallSuper
  Future close() async {
    logger.fine(
        "ApplicationChannel(${server.identifier}).close: closing messageHub");
    await messageHub.close();
  }

  /// Creates an OpenAPI document for the components and paths in this channel.
  ///
  /// This method invokes [entryPoint] and [prepare] before starting the documentation process.
  ///
  /// The documentation process first invokes [documentComponents] on this channel. Every controller in the channel will have its
  /// [documentComponents] methods invoked. Any declared property
  /// of this channel that implements [APIComponentDocumenter] will have its [documentComponents]
  /// method invoked. If there services that are part of the application, but not stored as properties of this channel, you may override
  /// [documentComponents] in your subclass to add them. You must call the superclass' implementation of [documentComponents].
  ///
  /// After components have been documented, [APIOperationDocumenter.documentPaths] is invoked on [entryPoint]. The controllers
  /// of the channel will add paths and operations to the document during this process.
  ///
  /// This method should not be overridden.
  ///
  /// [projectSpec] should contain the keys `name`, `version` and `description`.
  Future<APIDocument> documentAPI(Map<String, dynamic> projectSpec) async {
    final doc = APIDocument()..components = APIComponents();
    final root = entryPoint;
    root.didAddToChannel();

    final context = APIDocumentContext(doc);
    documentComponents(context);

    doc.paths = root.documentPaths(context);

    doc.info = APIInfo(
        projectSpec["name"] as String, projectSpec["version"] as String,
        description: projectSpec["description"] as String);

    await context.finalize();

    return doc;
  }

  @mustCallSuper
  @override
  void documentComponents(APIDocumentContext registry) {
    entryPoint.documentComponents(registry);

    (RuntimeContext.current[runtimeType] as ChannelRuntime)
        .getDocumentableChannelComponents(this)
        .forEach((component) {
      component.documentComponents(registry);
    });
  }
}

/// An object that sends and receives messages between [ApplicationChannel]s.
///
/// You use this object to share information between isolates. Each [ApplicationChannel] has a property of this type. A message sent through this object
/// is received by every other channel through its hub.
///
/// To receive messages in a hub, add a listener via [listen]. To send messages, use [add].
///
/// For example, an application may want to send data to every connected websocket. A reference to each websocket
/// is only known to the isolate it established a connection on. This data must be sent to each isolate so that each websocket
/// connected to that isolate can send the data:
///
///         router.route("/broadcast").linkFunction((req) async {
///           var message = await req.body.decodeAsString();
///           websocketsOnThisIsolate.forEach((s) => s.add(message);
///           messageHub.add({"event": "broadcastMessage", "data": message});
///           return Response.accepted();
///         });
///
///         messageHub.listen((event) {
///           if (event is Map && event["event"] == "broadcastMessage") {
///             websocketsOnThisIsolate.forEach((s) => s.add(event["data"]);
///           }
///         });
class ApplicationMessageHub extends Stream<dynamic> implements Sink<dynamic> {
  final Logger _logger = Logger("aqueduct");
  final StreamController<dynamic> _outboundController =
      StreamController<dynamic>();
  final StreamController<dynamic> _inboundController =
      StreamController<dynamic>.broadcast();

  /// Adds a listener for messages from other hubs.
  ///
  /// You use this method to add listeners for messages from other hubs.
  /// When another hub [add]s a message, this hub will receive it on [onData].
  ///
  /// [onError], if provided, will be invoked when this isolate tries to [add] invalid data. Only the isolate
  /// that failed to send the data will receive [onError] events.
  @override
  StreamSubscription<dynamic> listen(void onData(dynamic event),
          {Function onError, void onDone(), bool cancelOnError = false}) =>
      _inboundController.stream.listen(onData,
          onError: onError ??
              (err, StackTrace st) =>
                  _logger.severe("ApplicationMessageHub error", err, st),
          onDone: onDone,
          cancelOnError: cancelOnError);

  /// Sends a message to all other hubs.
  ///
  /// [event] will be delivered to all other isolates that have set up a callback for [listen].
  ///
  /// [event] must be isolate-safe data - in general, this means it may not be or contain a closure. Consult the API reference `dart:isolate` for more details. If [event]
  /// is not isolate-safe data, an error is delivered to [listen] on this isolate.
  @override
  void add(dynamic event) {
    _outboundController.sink.add(event);
  }

  @override
  Future close() async {
    if (!_outboundController.hasListener) {
      _outboundController.stream.listen(null);
    }

    if (!_inboundController.hasListener) {
      _inboundController.stream.listen(null);
    }

    await _outboundController.close();
    await _inboundController.close();
  }
}

abstract class ChannelRuntime {
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(
    ApplicationChannel channel);

  Type get channelType;

  String get name;
  Uri get libraryUri;
  IsolateEntryFunction get isolateEntryPoint;

  ApplicationChannel instantiateChannel();

  Future runGlobalInitialization(ApplicationOptions config);
}

