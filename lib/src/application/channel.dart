import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import '../http/http.dart';
import 'application.dart';
import 'package:aqueduct/src/application/service_registry.dart';

/// Subclasses of this type initialize an application's routes and services.
///
/// The behavior of an Aqueduct application is defined by subclassing this type and overriding its lifecycle callback methods. An
/// Aqueduct application may have exactly one subclass of this type declared in its `lib/` directory.
///
/// At minimum, a subclass must override [entryPoint] to return the first instance of [RequestController] that receives a new HTTP request.
/// This instance is typically a [Router]. An example minimum application follows:
///
///       class MyChannel extends ApplicationChannel {
///         RequestController get entryPoint {
///           final router = new Router();
///           router.route("/endpoint").listen((req) => new Response.ok('Hello, world!'));
///           return router;
///         }
///       }
///
/// [entryPoint] is the root of the application channel. It receives an HTTP request that flows through the channel until it is responded to.
///
/// Other forms of initialization, e.g. creating a service that interact with a database, should be initialized in [prepare]. This method is invoked
/// prior to [entryPoint] so that any services it creates can be injected into the [RequestController]s in the channel.
///
/// An instance of this type is created for each isolate the running application spawns. The number of isolates spawned is determined by an argument to [Application.start]
/// (which often comes from the command-line tool `aqueduct serve`). Any initialization that occurs in subclasses of this type will be called for each instance.
///
/// For initialization that must occur only once per application, you may implement the *static* method [initializeApplication] in a subclass of this type.
/// The signature of this method is ([ApplicationConfiguration]) -> [Future], for example:
///
///         class Channel extends ApplicationChannel {
///           static Future initializeApplication(ApplicationConfiguration config) async {
///             // Do one-time setup here
///           }
///           ...
///         }
///
/// This method is executed in the main isolate of the application, prior to any [ApplicationChannel]s being instantiated. Its values cannot directly be accessed by the isolates that are spawned
/// to serve requests through their [entryPoint]. See the documentation for [initializeApplication] for passing values computed in this method to each instance
/// of [ApplicationChannel].
///
/// [ApplicationChannel] instances may pass values to each other through [messageHub].
abstract class ApplicationChannel extends Object with APIDocumentable {
  /// One-time setup method for an application.
  ///
  /// This method is invoked as the first step during application startup. It is only invoked once per application, whereas other initialization
  /// methods are invoked once per isolate. Implement this method in an application's [ApplicationChannel] subclass. If you are sharing some resource
  /// across isolates, it must be instantiated in this method.
  ///
  ///         class MyChannel extends ApplicationChannel {
  ///           static Future initializeApplication(ApplicationConfiguration config) async {
  ///
  ///           }
  ///
  /// Any modifications to [config] will be available in each [ApplicationChannel] and therefore must be isolate-safe data. Do not configure
  /// types like [HTTPCodecRepository], [CORSPolicy.defaultPolicy] or any other value that isn't explicitly passed through [config].
  ///
  /// * Note that static methods are not inherited in Dart and therefore you are not overriding this method. The declaration of this method in the base [ApplicationChannel] class
  /// is for documentation purposes.
  static Future initializeApplication(ApplicationConfiguration config) async {}

  /// The logger of this instance
  Logger get logger => new Logger("aqueduct");

  /// This instance's owning server.
  ///
  /// Reference back to the owning server that adds requests into this channel.
  ApplicationServer get server => _server;
  set server(ApplicationServer server) {
    _server = server;
    messageHub._outboundController.stream.listen(server.sendApplicationEvent);
    server.hubSink = messageHub._inboundController.sink;
  }
  ApplicationServer _server;

  /// Sends and receives messages to other isolates running a [ApplicationChannel].
  ///
  /// Messages may be sent to other instances of this type via [ApplicationMessageHub.add]. An instance of this type
  /// may listen for those messages via [ApplicationMessageHub.listen]. See [ApplicationMessageHub] for more details.
  final ApplicationMessageHub messageHub = new ApplicationMessageHub();

  /// The context used for setting up HTTPS in an application.
  ///
  /// By default, this value is null. When null, an [Application] using this instance will listen over HTTP, and not HTTPS.
  /// If this instance [configuration] has non-null values for both [ApplicationConfiguration.certificateFilePath] and [ApplicationConfiguration.privateKeyFilePath],
  /// this value is a valid [SecurityContext] configured to use the certificate chain and private key as indicated by the configuration. The listening server
  /// will allow connections over HTTPS only. This getter is only invoked once per instance, after [entryPoint] is invoked.
  ///
  /// You may override this getter to provide a customized [SecurityContext].
  SecurityContext get securityContext {
    if (configuration?.certificateFilePath == null || configuration?.privateKeyFilePath == null) {
      return null;
    }

    return new SecurityContext()
      ..useCertificateChain(configuration.certificateFilePath)
      ..usePrivateKey(configuration.privateKeyFilePath);
  }

  /// Configuration options from the application.
  ///
  /// Options allow passing of application-specific information - like database connection information -
  /// from configuration data. This property is set in the constructor.
  ApplicationConfiguration configuration;

  /// The first [RequestController] to receive HTTP requests.
  ///
  /// Subclasses must override this getter to provide the first controller in the application channel to handle an HTTP request.
  /// This property is most often a configured [Router], but could be any type of [RequestController].
  ///
  /// This method is invoked exactly once for each instance, and the result is stored throughout the remainder of the application's lifetime.
  /// This method must fully configure the entire application channel; no controllers may be added to the channel after this method completes.
  ///
  /// This method is always invoked after [prepare].
  RequestController get entryPoint;

  /// Initialization callback.
  ///
  /// This method allows this instance to perform any initialization (other than setting up the [entryPoint]). This method
  /// is often used to set up services that [RequestController]s use to fulfill their duties. This method is invoked
  /// prior to [entryPoint], so that the services it creates can be injected into [RequestController]s.
  Future prepare() async {}

  /// Executed after the instance has been initialized, but right before it will start receiving requests.
  ///
  /// Override this method to take action just before [entryPoint] starts receiving requests. By default, does nothing.
  void willStartReceivingRequests() {}

  /// Closes this instance.
  ///
  /// Tell the channel that no further requests will be added, and it may release any resources it is using. Prefer using [ApplicationServiceRegistry]
  /// to overriding this method.
  ///
  /// If you do override this method, you must call the super implementation. The default behavior of this method removes
  /// any listeners from [logger], so it is advantageous to invoke the super implementation at the end of the override.
  Future close() async {
    logger.fine("ApplicationChannel(${server.identifier}).close: closing messageHub");
    await messageHub.close();
    logger.fine("ApplicationChannel(${server.identifier}).close: clear logger listeners");
    logger?.clearListeners();
  }

  @override
  APIDocument documentAPI(PackagePathResolver resolver) {
    var doc = new APIDocument();
    final root = entryPoint;
    root.prepare();

    doc.paths = root.documentPaths(resolver);
    doc.securitySchemes = documentSecuritySchemes(resolver);

    var host = new Uri(scheme: "http", host: "localhost");
    if (doc.hosts.length > 0) {
      host = doc.hosts.first.uri;
    }

    doc.securitySchemes?.values?.forEach((scheme) {
      if (scheme.isOAuth2) {
        var authCodePath = _authorizationPath(doc.paths);
        if (authCodePath != null) {
          scheme.authorizationURL = host.resolve(authCodePath).toString();
        }

        var tokenPath = _authorizationTokenPath(doc.paths);
        if (tokenPath != null) {
          scheme.tokenURL = host.resolve(tokenPath).toString();
        }
      }
    });

    var distinct = (Iterable<ContentType> items) {
      var retain = <ContentType>[];

      return items.where((ct) {
        if (!retain.any((retained) =>
            ct.primaryType == retained.primaryType &&
            ct.subType == retained.subType &&
            ct.charset == retained.charset)) {
          retain.add(ct);
          return true;
        }

        return false;
      }).toList();
    };
    doc.consumes = distinct(doc.paths.expand((p) => p.operations.expand((op) => op.consumes)));
    doc.produces = distinct(doc.paths.expand((p) => p.operations.expand((op) => op.produces)));

    return doc;
  }

  /// Returns the subclass of [ApplicationChannel] found in an application library.
  static Type get defaultType {
    var channelType = reflectClass(ApplicationChannel);
    var classes = currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .where((decl) => decl is ClassMirror && decl.isSubclassOf(channelType) && decl.reflectedType != ApplicationChannel)
        .map((decl) => decl as ClassMirror)
        .toList();

    if (classes.length == 0) {
      return null;
    }

    return classes.first.reflectedType;
  }

  String _authorizationPath(List<APIPath> paths) {
    var op = paths.expand((p) => p.operations).firstWhere((op) {
      return op.method.toLowerCase() == "post" &&
          op.responses.any((resp) {
            return resp.statusCode == HttpStatus.MOVED_TEMPORARILY &&
                ["client_id", "username", "password", "state"].every((qp) {
                  return op.parameters.map((apiParam) => apiParam.name).contains(qp);
                });
          });
    }, orElse: () => null);

    if (op == null) {
      return null;
    }

    var path = paths.firstWhere((p) => p.operations.contains(op));
    return path.path;
  }

  String _authorizationTokenPath(List<APIPath> paths) {
    var op = paths.expand((p) => p.operations).firstWhere((op) {
      return op.method.toLowerCase() == "post" &&
          op.responses.any((resp) {
            return ["access_token", "token_type", "expires_in", "refresh_token"]
                .every((property) => resp.schema?.properties?.containsKey(property) ?? false);
          });
    }, orElse: () => null);

    if (op == null) {
      return null;
    }

    var path = paths.firstWhere((p) => p.operations.contains(op));
    return path.path;
  }
}

/// Sends and receives messages from other isolates started by an [Application].
///
/// Messages added to an instance of this type - through [add] - are broadcast to every isolate running a [ApplicationChannel].
/// These messages are be received by [listen]ing to an instance of this type. A hub only receives messages from other isolates - it will not
/// receive messages that it sent.
///
/// This type implements both [Stream] (for receiving events from other isolates) and [Sink] (for sending events to other isolates).
///
/// For example, an application may want to send data to every connected websocket. A reference to each websocket
/// is only known to the isolate it established a connection on. This data must be sent to each isolate so that each websocket
/// connected to that isolate can send the data:
///
///         router.route("/broadcast").listen((req) async {
///           var message = await req.body.decodeAsString();
///           websocketsOnThisIsolate.forEach((s) => s.add(message);
///           messageHub.add({"event": "broadcastMessage", "data": message});
///           return new Response.accepted();
///         });
///
///         messageHub.listen((event) {
///           if (event is Map && event["event"] == "broadcastMessage") {
///             websocketsOnThisIsolate.forEach((s) => s.add(event["data"]);
///           }
///         });
class ApplicationMessageHub extends Stream<dynamic> implements Sink<dynamic> {
  Logger _logger = new Logger("aqueduct");
  StreamController<dynamic> _outboundController = new StreamController<dynamic>();
  StreamController<dynamic> _inboundController = new StreamController<dynamic>.broadcast();

  /// Adds a listener for data events from other isolates.
  ///
  /// When an isolate invokes [add], all other isolates receive that data in [onData].
  ///
  /// [onError], if provided, will be invoked when an isolate tries to [add] bad data. Only the isolate
  /// that failed to send the data will receive [onError] events.
  @override
  StreamSubscription<dynamic> listen(void onData(dynamic event),
          {Function onError, void onDone(), bool cancelOnError: false}) =>
      _inboundController.stream.listen(onData,
          onError: onError ?? (err, st) => _logger.severe("ApplicationMessageHub error", err, st),
          onDone: onDone,
          cancelOnError: cancelOnError);

  /// Sends a message to all other isolates.
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
