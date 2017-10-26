import 'dart:io';
import 'dart:async';
import 'dart:mirrors';

import 'package:logging/logging.dart';

import 'request_controller.dart';
import 'documentable.dart';
import '../application/application.dart';
import '../utilities/resource_registry.dart';
import 'http_codec_repository.dart';

/// Instances of this type are the root of an Aqueduct application.
///
/// [Application]s set up HTTP(S) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [RequestSink]. Must be subclassed. This class must be visible
/// to the application library file for tools like `aqueduct serve` to run Aqueduct applications.
///
/// A [RequestSink] must implement its constructor and [setupRouter]. HTTP requests to the [Application] are added to a [RequestSink]
/// for processing. The path the HTTP request takes is determined by the [RequestController] chains in [setupRouter]. A [RequestSink]
/// is also a [RequestController], but will always forward HTTP requests on to its [initialController].
///
/// Multiple instances of this type will be created for an [Application], each processing requests independently. Initialization code for
/// a [RequestSink] instance happens in the constructor, [setupRouter] and [willOpen] - in that order. The constructor instantiates resources,
/// [setupRouter] sets up routing and [willOpen] performs any tasks that occur asynchronously, like opening database connections. These initialization
/// steps occur for every instance of [RequestSink] in an application.
///
/// Any initialization that occurs once per application cannot
/// be performed in one of above methods. Instead, one-time initialization must be performed by implementing a static method in the
/// [RequestSink] subclass named `initializeApplication`. This method gets executed once when an application starts, prior to instances of [RequestSink]
/// being created. This method takes an [ApplicationConfiguration],
/// and may attach values to its [ApplicationConfiguration.options] for use by the [RequestSink] instances. This method is often used to
/// read configuration values from a file.
///
/// The signature of this method is ([ApplicationConfiguration]) -> [Future], for example:
///
///         class MyRequestSink extends RequestSink {
///           static Future initializeApplication(ApplicationConfiguration config) async {
///             // Do one-time setup here, e.g read configuration values from a file
///             var configurationValuesFromFile = ...;
///             config.options = configurationValuesFromFile;
///           }
///           ...
///         }
///
abstract class RequestSink extends Object with APIDocumentable {
  /// One-time setup method for an application.
  ///
  /// This method is invoked as the first step during application startup. It is only invoked once per application, whereas other initialization
  /// methods are invoked once per isolate. Implement this method in an application's [RequestSink] subclass. If you are sharing some resource
  /// across isolates, it must be instantiated in this method.
  ///
  ///         class MyRequestSink extends RequestSink {
  ///           static Future initializeApplication(ApplicationConfiguration config) async {
  ///
  ///           }
  ///
  /// Any modifications to [config] are available in each [RequestSink] and therefore must be isolate-safe data. Do not configure
  /// types like [HTTPCodecRepository] or any other types that are referenced by your code. If it can't be safely passed in [ApplicationConfiguration],
  /// it shouldn't be modified.
  ///
  /// * Note that static methods are not inherited in Dart and therefore you are not overriding this method. The declaration of this method in the base [RequestSink] class
  /// is for documentation purposes.
  static Future initializeApplication(ApplicationConfiguration config) async {}

  /// The logger of this instance
  Logger get logger => new Logger("aqueduct");

  /// This instance's owning server.
  ///
  /// Reference back to the owning server that adds requests into this sink.
  ApplicationServer get server => _server;

  set server(ApplicationServer server) {
    _server = server;
    messageHub._outboundController.stream.listen(server.sendApplicationEvent);
    server.hubSink = messageHub._inboundController.sink;
  }

  ApplicationServer _server;

  /// Sends and receives messages to other isolates running a [RequestSink].
  ///
  /// Messages may be sent to other instances of this type via [ApplicationMessageHub.add]. An instance of this type
  /// may listen for those messages via [ApplicationMessageHub.listen]. See [ApplicationMessageHub] for more details.
  final ApplicationMessageHub messageHub = new ApplicationMessageHub();

  /// The context used for setting up HTTPS in an application.
  ///
  /// By default, this value is null. When null, an [Application] using this instance will listen over HTTP, and not HTTPS.
  /// If this instance [configuration] has non-null values for both [ApplicationConfiguration.certificateFilePath] and [ApplicationConfiguration.privateKeyFilePath],
  /// this value is a valid [SecurityContext] configured to use the certificate chain and private key as indicated by the configuration. The listening server
  /// will allow connections over HTTPS only. This getter is only invoked once per instance, after [initializeApplication] and [RequestSink]'s constructor have been
  /// called, but before any other initialization occurs.
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

  RequestController get entry;

  /// Callback executed prior to this instance receiving requests.
  ///
  /// This method allows the instance to perform any asynchronous initialization prior to
  /// receiving requests. The instance will not start accepting HTTP requests until the [Future] returned from this method completes.
  Future willOpen() async {}

  /// Executed after the instance is is open to handle HTTP requests.
  ///
  /// This method is executed after the [HttpServer] is started and
  /// the [entry] has been set to start receiving requests.
  void didOpen() {}

  /// Closes this instance.
  ///
  /// Tell the sink that no further requests will be added, and it may release any resources it is using. Prefer using [ServiceRegistry]
  /// to overriding this method.
  ///
  /// If you do override this method, you must call the super implementation. The default behavior of this method removes
  /// any listeners from [logger], so it is advantageous to invoke the super implementation at the end of the override.
  Future close() async {
    logger.fine("RequestSink(${server.identifier}).close: closing messageHub");
    await messageHub.close();
    logger.fine("RequestSink(${server.identifier}).close: clear logger listeners");
    logger?.clearListeners();
  }

  @override
  APIDocument documentAPI(PackagePathResolver resolver) {
    var doc = new APIDocument();
    final root = entry;
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

  static Type get defaultSinkType {
    var sinkType = reflectClass(RequestSink);
    var classes = currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .where((decl) => decl is ClassMirror && decl.isSubclassOf(sinkType) && decl.reflectedType != RequestSink)
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
/// Messages added to an instance of this type - through [add] - are broadcast to every isolate running a [RequestSink].
/// These messages are be received by [listen]ing to an instance of this type. A hub only receives messages from other isolates - it will not
/// receive messages that it sent.
///
/// This type implements both [Stream] (for receiving events from other isolates) and [Sink] (for sending events to other isolates). Avoid
/// [Stream] methods such as [Stream.first], which will stop the hub from listening to future events.
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
