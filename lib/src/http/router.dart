import 'dart:io';
import 'dart:async';

import 'http.dart';
import 'route_specification.dart';
import 'route_node.dart';

/// Determines which [Controller] should receive a [Request] based on its path.
///
/// A router is a [Controller] that evaluates the path of a [Request] and determines which controller should be the next to receive it.
/// Valid paths for a [Router] are called *routes* and are added to a [Router] via [route].
///
/// Each [route] creates a new [Controller] that will receive all requests whose path match the route pattern.
/// If a request path does not match one of the registered routes, [Router] responds with 404 Not Found and does not pass
/// the request to another controller.
///
/// Unlike most [Controller]s, a [Router] may have multiple controllers it sends requests to. In most applications,
/// a [Router] is the [ApplicationChannel.entryPoint].
class Router extends Controller {
  /// Creates a new [Router].
  Router() {
    unmatchedController = _handleUnhandledRequest;
    policy.allowCredentials = false;
  }

  List<_RouteController> _routeControllers = [];
  RouteNode _rootRouteNode;
  List<String> _basePathSegments = [];
  Function _unmatchedController;

  /// A prefix for all routes on this instance.
  ///
  /// If this value is non-null, each [route] is prefixed by this value.
  ///
  /// For example, if a route is "/users" and the value of this property is "/api",
  /// a request's path must be "/api/users" to match the route.
  ///
  /// Trailing and leading slashes have no impact on this value.
  String get basePath => "/${_basePathSegments.join("/")}";
  set basePath(String bp) {
    _basePathSegments = bp.split("/").where((str) => str.isNotEmpty).toList();
  }

  /// Invoked when a [Request] does not match a registered route.
  ///
  /// If a [Request] has no matching route, this function will be called.
  ///
  /// By default, this function will send a 404 Not Found response.
  set unmatchedController(Future listener(Request req)) {
    _unmatchedController = listener;
  }


  /// Adds a route to this instance.
  ///
  /// Requests that match [pattern] will be sent to the [Controller] returned by this method. Controllers that
  /// should receive these requests should be attached to the returned [Controller] (via [pipe], [generate], or [listen]).
  ///
  /// The [pattern] must follow the rules of route patterns (see also http://aqueduct.io/docs/http/routing/).
  ///
  /// A pattern consists of one or more path segments, e.g. "/path" or "/path/to".
  ///
  /// A path segment can be:
  ///
  /// - A literal string (e.g. `users`)
  /// - A path variable: a literal string prefixed with `:` (e.g. `:id`)
  /// - A wildcard: the character `*`
  ///
  /// A path variable may contain a regular expression by placing the expression in parentheses immediately after the variable name. (e.g. `:id(/d+)`).
  ///
  /// A path segment is required by default. Path segments may be marked as optional
  /// by wrapping them in square brackets `[]`.
  ///
  /// Here are some example routes:
  ///
  ///         /users
  ///         /users/:id
  ///         /users/[:id]
  ///         /users/:id/friends/[:friendID]
  ///         /locations/:name([^0-9])
  ///         /files/*
  ///
  Controller route(String pattern) {
    var routeController = new _RouteController(
        RouteSpecification.specificationsForRoutePattern(pattern));
    _routeControllers.add(routeController);
    return routeController;
  }

  @override
  void prepare() {
    _rootRouteNode =
        new RouteNode(_routeControllers.expand((rh) => rh.patterns).toList());

    for (var c in _routeControllers) {
      c.prepare();
    }
  }

  /// Routers override this method to throw an exception. Use [route] instead.
  @override
  Controller pipe(Controller n) {
    throw new RouterException("Routers may not use pipe, use route instead.");
  }

  /// Routers override this method to throw an exception. Use [route] instead.
  @override
  Controller generate(Controller generatorFunction()) {
    throw new RouterException(
        "Routers may not use generate, use route instead.");
  }

  /// Routers override this method to throw an exception. Use [route] instead.
  @override
  Controller listen(
      FutureOr<RequestOrResponse> handler(
          Request request)) {
    throw new RouterException("Routers may not use listen, use route instead.");
  }

  @override
  Future receive(Request req) async {
    Controller next;
    try {
      var requestURISegmentIterator = req.raw.uri.pathSegments.iterator;

      if (req.raw.uri.pathSegments.isEmpty) {
        requestURISegmentIterator = [""].iterator;
      }

      for (var i = 0; i < _basePathSegments.length; i++) {
        requestURISegmentIterator.moveNext();
        if (_basePathSegments[i] != requestURISegmentIterator.current) {
          await _unmatchedController(req);
          return null;
        }
      }

      req.path = new HTTPRequestPath(req.raw.uri.pathSegments, segmentOffset: _basePathSegments.length);

      var node = _rootRouteNode.nodeForPathSegments(requestURISegmentIterator, req.path);
      if (node?.specification == null) {
        await _unmatchedController(req);
        return null;
      }
      req.path.specification = node.specification;

      next = node.controller;
    } catch (any, stack) {
      return handleError(req, any, stack);
    }

    return next?.receive(req);
  }

  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) {
    return _routeControllers
        .expand((rh) => rh.patterns)
        .map((RouteSpecification routeSpec) =>
            routeSpec.documentPaths(resolver).first)
        .toList();
  }

  @override
  String toString() {
    return _rootRouteNode.toString();
  }

  Future _handleUnhandledRequest(Request req) async {
    var response = new Response.notFound();
    if (req.acceptsContentType(ContentType.HTML)) {
      response
          ..body = "<html><h3>404 Not Found</h3></html>"
          ..contentType = ContentType.HTML;
    }

    applyCORSHeadersIfNecessary(req, response);
    await req.respond(response);
    logger.info("${req.toDebugString()}");
  }
}


class _RouteController extends Controller {
  /// Do not create instances of this class manually.
  _RouteController(this.patterns) {
    patterns.forEach((p) {
      p.controller = this;
    });
  }

  /// Route specifications for this controller.
  final List<RouteSpecification> patterns;
}

/// Thrown when a [Router] encounters an exception.
class RouterException implements Exception {
  RouterException(this.message);

  final String message;

  @override
  String toString() {
    return "RouterException: $message";
  }
}
