part of aqueduct;

/// A abstract class that concrete subclasses will implement to provide request handling behavior.
///
/// [Application]s set up HTTP(S) listeners, but do not do anything with them. The behavior of how an application
/// responds to requests is defined by its [RequestSink]. Must be subclassed.
abstract class RequestSink extends RequestController implements APIDocumentable {
  /// Default constructor.
  ///
  /// The default constructor takes a [Map] of configuration [options]. The constructor should initialize
  /// properties that will be used throughout the callbacks executed during initialization. For any code that requires async initialization,
  /// use [willOpen]. However, it is important to note that any properties that are used during initialization callbacks (like [addRoutes]) should be
  /// initialized in this constructor and not during [willOpen]. If properties that are needed during initialization callbacks
  /// must be initialized asynchronously, those properties should implement their own deferred initialization mechanism
  /// that can be triggered in [willOpen], but still must be initialized in this constructor.
  RequestSink(this.options);

  /// Documentation info for this stream.
  APIInfo apiInfo = new APIInfo();

  /// This stream's owning server.
  ///
  /// Reference back to the owning server sending requests into this stream.
  _Server server;

  /// This stream's router.
  ///
  /// The default router for a stream. Configure [router] by adding routes to it in [addRoutes].
  /// Using a router other than this router will impede the stream's ability to generate documentation.
  Router router = new Router();

  /// Configuration options from the application.
  ///
  /// Options allow passing of application-specific information - like database connection information -
  /// from configuration data. This property is set in the constructor.
  Map<String, dynamic> options;

  /// Returns the first controller in the responder stream.
  ///
  /// When a [Request] is delivered to the stream, this
  /// controller will be the first to act on it.  By default, this is [router].
  RequestController initialController() {
    return router;
  }

  /// Callback for implementing this stream's routing table.
  ///
  /// Routes should only be added in this method to this instance's [router]. This method will execute prior to [willOpen] being called,
  /// so any properties this stream needs to handle route setup must be set in this instance's constructor.
  void addRoutes();

  /// Callback executed prior to this stream receiving requests.
  ///
  /// This method allows the stream to perform any asynchronous initialization prior to
  /// receiving requests. The stream will not open until the [Future] returned from this method completes.
  Future willOpen() async {

  }

  /// Executed after the stream is attached to an [HttpServer].
  ///
  /// This method is executed after the [HttpServer] is started and
  /// the [initialController] has been set to start receiving requests.
  /// Because requests could potentially be queued prior to this stream
  /// being opened, a request could be received prior to this method being executed.
  void didOpen() {}

  /// Executed for each [Request] that will be sent to this stream.
  ///
  /// This method will run prior to each request being [receive]ed to this
  /// stream's [initialController]. Use this method to provide additional
  /// context to the request prior to it being handled.
  Future willReceiveRequest(Request request) async {

  }

  /// Document generator for stream.
  ///
  /// This method will return a new [APIDocument]. It will derive the [APIDocument.paths] from its [initialController],
  /// which must return a [List] of [APIPath]s. By default, the [initialController] is a [Router], which
  /// implements [Router.document] to return that list. However, if you change the [initialController], you
  /// must override its [document] method to return the same.
  @override
  APIDocument documentAPI(PackagePathResolver resolver) {
    var doc = new APIDocument()
      ..info = apiInfo;

    doc.paths = initialController().documentPaths(resolver);
    doc.securitySchemes = this.documentSecuritySchemes(resolver);

    var host = new Uri(scheme: "http", host: "localhost");
    if (doc.hosts.length > 0) {
      host = doc.hosts.first.uri;
    }

    doc.securitySchemes.values.forEach((scheme) {
      if (scheme.isOAuth2) {
        if (scheme.oauthFlow == APISecuritySchemeFlow.implicit
        || scheme.oauthFlow == APISecuritySchemeFlow.accessCode) {
          var morePath = _authorizationPath(doc.paths);
          if (morePath != null) {
            scheme.authorizationURL = host.resolve(morePath).toString();
          }
        }

        if (scheme.oauthFlow == APISecuritySchemeFlow.password
        || scheme.oauthFlow == APISecuritySchemeFlow.accessCode
        || scheme.oauthFlow == APISecuritySchemeFlow.application) {
          var morePath = _authorizationTokenPath(doc.paths);
          scheme.tokenURL = host.resolve(morePath).toString();
        }
      }
    });

    var distinct = (Iterable<ContentType> items) {
      var retain = <ContentType>[];

      return items.where((ct) {
        if (!retain.any((retained) =>
          ct.primaryType == retained.primaryType
          && ct.subType == retained.subType
          && ct.charset == retained.charset
        )) {
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

  String _authorizationPath(List<APIPath> paths) {
    var op = paths
        .expand((p) => p.operations)
        .firstWhere((op) {
          return op.method.toLowerCase() == "post"
              && op.responses.any((resp) {
                return resp.statusCode == HttpStatus.MOVED_TEMPORARILY
                  && ["client_id", "username", "password", "state"].every((qp) {
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
    var op = paths
        .expand((p) => p.operations)
        .firstWhere((op) {
          return op.method.toLowerCase() == "post" && op.responses.any((resp) {
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