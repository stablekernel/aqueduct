part of aqueduct;

/// A [Request] router to split requests onto separate streams based on their URI.
///
/// Instances of this class maintain a collection of streams for each route that has been registered with it.
/// A route is defined by a [String] format, for example:
///     router.addRoute("/users");
///     router.addRoute("/posts/:id");
///     router.addRoute("/things/[:id]");
///     router.addRoute("/numbers/:id(\d+)");
///     router.addRoute("/files/*");
///
/// Each route added to a [Router] creates a [Stream] of [Request]s that a handler can listen to.
class Router extends RequestHandler {
  List<ResourceRoute> routes;

  /// A string to be prepended to the beginning of every route this [Router] manages.
  ///
  /// For example, if this [Router]'s base route is "/api" and the routes "/users/"
  /// and "/posts" are added, the actual routes will be "/api/users" and "/api/posts".
  /// This property MUST be set prior to adding routes, an exception will be thrown
  /// otherwise.
  ///

  String get basePath => _basePath;
  void set basePath(String bp) {
    if (routes.length > 0) {
      throw new RouterException("Cannot alter basePath after adding routes.");
    }
    _basePath = bp;
  }

  String _basePath;

  /// How this router handles [Request]s that don't match its routes.
  ///
  /// If a [Request] delivered via [routeRequest] has no matching route in this [Router],
  /// this function will be called.
  /// By default, this handler will respond to the incoming [Request] with a 404 response,
  /// and does not forward or allow consumption of the [Request] for later handlers.
  Function get unhandledRequestHandler => _unhandledRequestHandler;
  void set unhandledRequestHandler(void handler(Request req)) {
    _unhandledRequestHandler = handler;
  }

  var _unhandledRequestHandler;

  /// Creates a new [Router].
  Router() {
    routes = [];
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  /// Adds a route to this router and provides a forwarding [RequestHandler] for all [Request]s that match that route to be delivered on.
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

  ResourceRoute _createRoute(String pattern) {
    if (basePath != null) {
      pattern = basePath + pattern;
    }

    // Strip out any extraneous /s
    var finalPattern = pattern.split("/").where((c) => c != "").join("/");

    var route = new ResourceRoute(new ResourcePattern(finalPattern), new RequestHandler());
    routes.add(route);

    return route;
  }

  @override
  Future deliver(Request req) async {
    for (var route in routes) {
      var routeMatch = route.pattern.matchUri(req.innerRequest.uri);

      if (routeMatch != null) {
        req.path = routeMatch;
        route.handler.deliver(req);
        return;
      }
    }

    _unhandledRequestHandler(req);
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    List<APIDocumentItem> items = [];

    for (var route in routes) {
      var routeItems = route.handler.document(resolver);

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

class ResourceRoute {
  final ResourcePattern pattern;
  final RequestHandler handler;

  ResourceRoute(this.pattern, this.handler);
}

class RouterException implements Exception {
  final String message;
  RouterException(this.message);

  String toString() {
    return "RouterException: $message";
  }
}
