part of monadart;

/// A [ResourceRequest] router to split requests onto separate streams based on their URI.
///
/// Instances of this class maintain a collection of streams for each route that has been registered with it.
/// A route is defined by a [String] format, for example:
///     router.addRoute("/users");
///     router.addRoute("/posts/:id");
///     router.addRoute("/things/[:id]");
///     router.addRoute("/numbers/:id(\d+)");
///     router.addRoute("/files/*");
///
/// Each route added to a [Router] creates a [Stream] of [ResourceRequest]s that a handler can listen to.
class Router extends RequestHandler {
  List<_ResourceRoute> _routes;

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
      throw new _RouterException("Cannot alter basePath after adding routes.");
    }
    _basePath = bp;
  }

  String _basePath;

  /// How this router handles [ResourceRequest]s that don't match its routes.
  ///
  /// If a [ResourceRequest] delivered via [routeRequest] has no matching route in this [Router],
  /// this function will be called.
  /// By default, this handler will respond to the incoming [ResourceRequest] with a 404 response,
  /// and does not forward or allow consumption of the [ResourceRequest] for later handlers.
  Function get unhandledRequestHandler => _unhandledRequestHandler;
  void set unhandledRequestHandler(void handler(ResourceRequest req)) {
    _unhandledRequestHandler = handler;
  }

  var _unhandledRequestHandler;

  /// Creates a new [Router].
  Router() {
    _routes = [];
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  /// Adds a route to this router and provides a forwarding [RequestHandler] for all [ResourceRequest]s that match that route to be delivered on.
  ///
  /// A router manages route to [Stream] mappings that are added through this method.
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
    return _createRoute(pattern).handler;
  }

  _ResourceRoute _createRoute(String pattern) {
    if (basePath != null) {
      pattern = basePath + pattern;
    }

    // Strip out any extraneous /s
    var finalPattern = pattern.split("/").where((c) => c != "").join("/");

    var route = new _ResourceRoute(
        new ResourcePattern(finalPattern), new RequestHandler());
    _routes.add(route);

    return route;
  }

  @override
  void deliver(ResourceRequest req) {
    for (var route in _routes) {
      var routeMatch = route.pattern.matchUri(req.innerRequest.uri);

      if (routeMatch != null) {
        logger.finest("Router: match for ${req.innerRequest.uri}.");
        req.path = routeMatch;
        route.handler.deliver(req);
        return;
      }
    }

    logger.finest("Router: no matching route for ${req.innerRequest.uri}.");
    _unhandledRequestHandler(req);
  }

  void _handleUnhandledRequest(ResourceRequest req) {
    req.response.statusCode = HttpStatus.NOT_FOUND;
    req.response.close();
  }
}

class _ResourceRoute {
  final ResourcePattern pattern;
  final RequestHandler handler;

  _ResourceRoute(this.pattern, this.handler);
}

class _RouterException implements Exception {
  final String message;
  _RouterException(this.message);
}
