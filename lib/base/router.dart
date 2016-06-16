part of aqueduct;

/// A router to split requests based on their URI.
///
/// Instances of this class maintain a collection of [RouteHandler]s for each route that has been registered with it.
/// [RouteHandler]s are subclasses of [RequestHandler] so that further [RequestHandler]s can be chained off of it.
/// When a [Request] is delivered to the router, it will pass it on to the associated [RouteHandler] or respond to the
/// [Request] with a 404 status code.
///
/// A route is defined by a [String] format, for example:
///     router.route("/users");
///     router.route("/posts/:id");
///     router.route("/things/[:id]");
///     router.route("/numbers/:id(\d+)");
///     router.route("/files/*");
///
class Router extends RequestHandler {
  /// Creates a new [Router].
  Router() {
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  List<RouteHandler> _routes = [];

  /// A string to be prepended to the beginning of every route this [Router] manages.
  ///
  /// For example, if this [Router]'s base route is "/api" and the routes "/users/"
  /// and "/posts" are added, the actual routes will be "/api/users" and "/api/posts".
  /// This property MUST be set prior to adding routes, an exception will be thrown
  /// otherwise.
  ///
  String get basePath => _basePath;
  void set basePath(String bp) {
    if (_routes.length > 0) {
      throw new RouterException("Cannot alter basePath after adding routes.");
    }
    _basePath = bp;
  }
  String _basePath;

  /// How this router handles [Request]s that don't match its routes.
  ///
  /// If a [Request] has no matching route, this function will be called.
  /// By default, this function will respond to the incoming [Request] with a 404 response,
  /// and does not forward or allow consumption of the [Request] for later handlers.
  Function get unhandledRequestHandler => _unhandledRequestHandler;
  void set unhandledRequestHandler(void handler(Request req)) {
    _unhandledRequestHandler = handler;
  }
  var _unhandledRequestHandler;


  /// Adds a route to this router and provides a forwarding [RequestHandler] for all [Request]s that match that route to be delivered on.
  ///
  /// This method will create an instance of a [RouteHandler] and attach it to this router, returning the [RouteHandler] instance
  /// to allow further [RequestHandler]s to be attached.
  /// The [pattern] must follow the rules of route patterns (see the guide for more explanation).
  /// A pattern consists of one or more path segments. A path segment can be a constant string,
  /// a path variable (a word prefixed with the : character) or the wildcard character (the asterisk character *)
  ///       /constantString/:pathVariable/*
  /// Path variables may optionally contain regular expression syntax within parentheses to constrain their matches.
  ///       /:pathVariable(\d+)
  /// Path segments may be marked as optional by using square brackets around the segment. The opening square
  /// bracket must follow the preceding path delimeter (/).
  ///       /constantString/[:optionalVariable]
  /// Routes may have multiple optional segments, but they must be nested.
  ///       /constantString/[:optionalVariable/[optionalConstantString]]
  RequestHandler route(String pattern) {
    return _createRoute(pattern);
  }

  RouteHandler _createRoute(String pattern) {
    if (basePath != null) {
      pattern = basePath + pattern;
    }

    // Strip out any extraneous /s
    var finalPattern = pattern.split("/").where((c) => c != "").join("/");

    var route = new RouteHandler(new RoutePattern(finalPattern));
    _routes.add(route);

    return route;
  }

  @override
  Future deliver(Request req) async {
    for (var route in _routes) {
      var routeMatch = route.pattern.matchUri(req.innerRequest.uri);

      if (routeMatch != null) {
        req.path = routeMatch;
        route.deliver(req);
        return;
      }
    }

    _unhandledRequestHandler(req);
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    List<APIDocumentItem> items = [];

    for (var route in _routes) {
      var routeItems = route.document(resolver);

      items.addAll(routeItems.map((i) {
        i.path = (basePath ?? "") + route.pattern.documentedPathWithVariables(i.pathParameters);
        return i;
      }));
    }

    return items;
  }

  void _handleUnhandledRequest(Request req) {
    var response = new Response.notFound();
    _applyCORSHeadersIfNecessary(req, response);
    req.respond(response);
    logger.info(req.toDebugString());
  }
}

class RouteHandler extends RequestHandler {
  final RoutePattern pattern;

  RouteHandler(this.pattern);
}

class RouterException implements Exception {
  final String message;
  RouterException(this.message);

  String toString() {
    return "RouterException: $message";
  }
}
