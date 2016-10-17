part of aqueduct;

/// A router to split requests based on their URI.
///
/// Instances of this class maintain a collection of [RouteController]s for each route that has been registered with it.
/// [RouteController]s are subclasses of [RequestController] so that further [RequestController]s can be chained off of it.
/// When a [Request] is delivered to the router, it will pass it on to the associated [RouteController] or respond to the
/// [Request] with a 404 status code.
///
/// A route is defined by a [String] format, for example:
///     router.route("/users");
///     router.route("/posts/:id");
///     router.route("/things[/:id]");
///     router.route("/numbers/:id(\d+)");
///     router.route("/files/*");
///
class Router extends RequestController {
  /// Creates a new [Router].
  Router() {
    unhandledRequestController = _handleUnhandledRequest;
  }

  List<RouteController> _routeControllers = [];
  _RouteNode _rootRouteNode;

  /// A string to be prepended to the beginning of every route this [Router] manages.
  ///
  /// For example, if this [Router]'s base path is "/api" and the route "/users"
  /// is added, the actual route will be "/api/users". Using this property will make route matching
  /// more efficient than including the base path in each route.
  String get basePath => _basePathSegments.join("/");
  set basePath(String bp) {
    _basePathSegments = bp.split("/").where((str) => !str.isEmpty).toList();
  }
  List<String> _basePathSegments = [];

  /// How this router handles [Request]s that don't match its routes.
  ///
  /// If a [Request] has no matching route, this function will be called.
  /// By default, this function will respond to the incoming [Request] with a 404 response,
  /// and does not forward or allow consumption of the [Request] for later controllers.
  Function get unhandledRequestController => _unhandledRequestController;
  void set unhandledRequestController(void listener(Request req)) {
    _unhandledRequestController = listener;
  }
  var _unhandledRequestController;


  /// Adds a route to this router and provides a forwarding [RequestController] for all [Request]s that match that route to be delivered on.
  ///
  /// This method will create an instance of a [RouteController] and attach it to this router, returning the [RouteController] instance
  /// to allow further [RequestController]s to be attached.
  /// The [pattern] must follow the rules of route patterns (see the guide for more explanation).
  /// A pattern consists of one or more path segments. A path segment can be a constant string,
  /// a path variable (a word prefixed with the : character) or the wildcard character (the asterisk character *)
  ///       /constantString/:pathVariable/*
  /// Path variables may optionally contain regular expression syntax within parentheses to constrain their matches.
  ///       /:pathVariable(\d+)
  /// Path segments may be marked as optional by using square brackets around the segment. The opening square
  /// bracket may be on either side of the preceding path delimiter (/) with no effect.
  ///       /constantString/[:optionalVariable]
  ///       /constantString[/:optionalVariable]
  /// Routes may have multiple optional segments, but they must be nested.
  ///       /constantString/[:optionalVariable/[optionalConstantString]]
  /// Routes may also contain multiple path segments in the same optional grouping.
  ///       /constantString/[segment1/segment2]
  RequestController route(String pattern) {
    var routeController = new RouteController(RouteSpecification.specificationsForRoutePattern(pattern));
    _routeControllers.add(routeController);
    return routeController;
  }

  /// Invoke on this router once all routes are added.
  ///
  /// If you are using the default router from [RequestSink], this method is called for you. Otherwise,
  /// you must call this method after all routes have been added to build a tree of routes for optimized route finding.
  void finalize() {
    _rootRouteNode = new _RouteNode(_routeControllers.expand((rh) => rh.patterns).toList());
  }


  RequestController pipe(RequestController n) {
    throw new RouterException("Routers may not use pipe, use route instead.");
  }

  RequestController generate(RequestController generatorFunction()) {
    throw new RouterException("Routers may not use generate, use route instead.");
  }

  RequestController listen(Future<RequestControllerEvent> requestControllerFunction(Request request)) {
    throw new RouterException("Routers may not use listen, use route instead.");
  }

  @override
  Future receive(Request req) async {
    var requestURISegmentIterator = req.innerRequest.uri.pathSegments.iterator;
    if (_basePathSegments.length > 0) {
      for (var i = 0; i < _basePathSegments.length; i++) {
        requestURISegmentIterator.moveNext();
        if (_basePathSegments[i] != requestURISegmentIterator.current) {
          _unhandledRequestController(req);
          return;
        }
      }
    }

    var remainingSegments = <String>[];
    while (requestURISegmentIterator.moveNext()) {
      remainingSegments.add(requestURISegmentIterator.current);
    }
    if (remainingSegments.isEmpty) {
      remainingSegments = [""];
    }

    var node = _rootRouteNode.nodeForPathSegments(remainingSegments);
    if (node?.specification != null) {
      var requestPath = new RequestPath(node.specification, remainingSegments);
      req.path = requestPath;
      node.controller.receive(req);
      return;
    }

    _unhandledRequestController(req);
  }

  /// Returns a [List] of [APIPath]s configured in this router.
  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) {
    return _routeControllers
        .expand((rh) => rh.patterns)
        .map((RouteSpecification routeSpec) => routeSpec.documentPaths(resolver).first)
        .toList();
  }

  void _handleUnhandledRequest(Request req) {
    var response = new Response.notFound();
    _applyCORSHeadersIfNecessary(req, response);
    req.respond(response);
    logger.info("${req.toDebugString()}");
  }
}

class RouteController extends RequestController {
  RouteController(this.patterns) {
    patterns.forEach((p) {
      p.controller = this;
    });
  }

  final List<RouteSpecification> patterns;
}

class RouterException implements Exception {
  final String message;
  RouterException(this.message);

  String toString() {
    return "RouterException: $message";
  }
}
