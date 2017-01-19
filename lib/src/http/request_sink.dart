import 'dart:io';
import 'dart:async';
import 'dart:mirrors';

import 'request.dart';
import 'request_controller.dart';
import 'documentable.dart';
import 'router.dart';
import '../application/application.dart';

/// Instances of this class are responsible for setting up routing and resources used by an [Application].
///
/// [Application]s set up HTTP(S) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [RequestSink]. Must be subclassed.
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
abstract class RequestSink extends RequestController
    implements APIDocumentable {
  /// Default constructor.
  ///
  /// The default constructor takes a [Map] of configuration [configuration]. This [Map] is the same [Map] in [ApplicationConfiguration.options].
  ///
  /// For any code that requires async initialization, use [willOpen]. However, it is important to note that any properties that are used during initialization callbacks (like [setupRouter]) should be
  /// initialized in this constructor and not during [willOpen]. If properties that are needed during initialization callbacks
  /// must be initialized asynchronously, those properties should implement their own deferred initialization mechanism
  /// that can be triggered in [willOpen], but still must be initialized in this constructor.
  RequestSink(this.configuration);

  /// Documentation info for this instance.
  APIInfo apiInfo = new APIInfo();

  /// This instance's owning server.
  ///
  /// Reference back to the owning server that adds requests into this sink.
  ApplicationServer server;

  /// This instance's router.
  ///
  /// The default router for this instance. Configure [router] by adding routes to it in [setupRouter].
  /// Using a router other than this router will impede the sink's ability to generate documentation.
  Router router = new Router();

  /// Configuration options from the application.
  ///
  /// Options allow passing of application-specific information - like database connection information -
  /// from configuration data. This property is set in the constructor.
  ApplicationConfiguration configuration;

  /// Returns the first [RequestController] to handle HTTP requests added to this sink.
  ///
  /// When a [Request] is delivered to this instance, this
  /// controller will be the first to act on it.  By default, this is [router].
  RequestController get initialController => router;

  /// Callback for implementing this instances's routing table.
  ///
  /// Routes should only be added to [router] in this method. This method will execute prior to [willOpen] being called,
  /// so any properties this instance needs to handle route setup must be set in this instance's constructor. The argument
  /// to this method is the same instance as the property [RequestSink.router].
  void setupRouter(Router router);

  /// Callback executed prior to this instance receiving requests.
  ///
  /// This method allows the instance to perform any asynchronous initialization prior to
  /// receiving requests. The instance will not start accepting HTTP requests until the [Future] returned from this method completes.
  Future willOpen() async {}

  /// Executed after the instance is is open to handle HTTP requests.
  ///
  /// This method is executed after the [HttpServer] is started and
  /// the [initialController] has been set to start receiving requests.
  /// Because requests could potentially be queued prior to this instance
  /// being opened, a request could be received prior to this method being executed.
  void didOpen() {}

  /// Executed for each [Request] that will be sent to this instance.
  ///
  /// This method will run prior to each request being [receive]ed to this
  /// instance's [initialController]. Use this method to provide additional
  /// context to the request prior to it being handled.
  Future willReceiveRequest(Request request) async {}

  @override
  APIDocument documentAPI(PackagePathResolver resolver) {
    var doc = new APIDocument()..info = apiInfo;

    doc.paths = initialController.documentPaths(resolver);
    doc.securitySchemes = this.documentSecuritySchemes(resolver);

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
    doc.consumes = distinct(
        doc.paths.expand((p) => p.operations.expand((op) => op.consumes)));
    doc.produces = distinct(
        doc.paths.expand((p) => p.operations.expand((op) => op.produces)));

    return doc;
  }

  static Type get defaultSinkType {
    var sinkType = reflectClass(RequestSink);
    var classes = currentMirrorSystem()
        .libraries
        .values
        .where(
            (lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
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
                  return op.parameters
                      .map((apiParam) => apiParam.name)
                      .contains(qp);
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
                .every((property) =>
                    resp.schema?.properties?.containsKey(property) ?? false);
          });
    }, orElse: () => null);

    if (op == null) {
      return null;
    }

    var path = paths.firstWhere((p) => p.operations.contains(op));
    return path.path;
  }
}
