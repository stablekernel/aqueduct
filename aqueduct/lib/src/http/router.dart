import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';

import 'http.dart';
import 'route_node.dart';
import 'route_specification.dart';

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
  Router({String basePath, Future notFoundHandler(Request request)})
      : _unmatchedController = notFoundHandler,
        _basePathSegments =
            basePath?.split("/")?.where((str) => str.isNotEmpty)?.toList() ??
                [] {
    policy.allowCredentials = false;
  }

  final _RootNode _root = _RootNode();
  final List<_RouteController> _routeControllers = [];
  final List<String> _basePathSegments;
  final Function _unmatchedController;

  /// A prefix for all routes on this instance.
  ///
  /// If this value is non-null, each [route] is prefixed by this value.
  ///
  /// For example, if a route is "/users" and the value of this property is "/api",
  /// a request's path must be "/api/users" to match the route.
  ///
  /// Trailing and leading slashes have no impact on this value.
  String get basePath => "/${_basePathSegments.join("/")}";

  /// Adds a route that [Controller]s can be linked to.
  ///
  /// Routers allow for multiple linked controllers. A request that matches [pattern]
  /// will be sent to the controller linked to this method's return value.
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
  Linkable route(String pattern) {
    var routeController = _RouteController(
        RouteSpecification.specificationsForRoutePattern(pattern));
    _routeControllers.add(routeController);
    return routeController;
  }

  @override
  void didAddToChannel() {
    _root.node =
        RouteNode(_routeControllers.expand((rh) => rh.specifications).toList());

    for (var c in _routeControllers) {
      c.didAddToChannel();
    }
  }

  /// Routers override this method to throw an exception. Use [route] instead.
  @override
  Linkable link(Controller generatorFunction()) {
    throw ArgumentError(
        "Invalid link. 'Router' cannot directly link to controllers. Use 'route'.");
  }

  @override
  Linkable linkFunction(FutureOr<RequestOrResponse> handle(Request request)) {
    throw ArgumentError(
        "Invalid link. 'Router' cannot directly link to functions. Use 'route'.");
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
          await _handleUnhandledRequest(req);
          return null;
        }
      }

      final node =
          _root.node.nodeForPathSegments(requestURISegmentIterator, req.path);
      if (node?.specification == null) {
        await _handleUnhandledRequest(req);
        return null;
      }
      req.path.setSpecification(node.specification,
          segmentOffset: _basePathSegments.length);

      next = node.controller;
    } catch (any, stack) {
      return handleError(req, any, stack);
    }

    // This line is intentionally outside of the try block
    // so that this object doesn't handle exceptions for 'next'.
    return next?.receive(req);
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    throw StateError("Router invoked handle. This is a bug.");
  }

  @override
  Map<String, APIPath> documentPaths(APIDocumentContext context) {
    return _routeControllers.fold(<String, APIPath>{}, (prev, elem) {
      prev.addAll(elem.documentPaths(context));
      return prev;
    });
  }

  @override
  void documentComponents(APIDocumentContext context) {
    _routeControllers.forEach((_RouteController controller) {
      controller.documentComponents(context);
    });
  }

  @override
  String toString() {
    return _root.node.toString();
  }

  Future _handleUnhandledRequest(Request req) async {
    if (_unmatchedController != null) {
      return _unmatchedController(req);
    }
    var response = Response.notFound();
    if (req.acceptsContentType(ContentType.html)) {
      response
        ..body = "<html><h3>404 Not Found</h3></html>"
        ..contentType = ContentType.html;
    }

    applyCORSHeadersIfNecessary(req, response);
    await req.respond(response);
    logger.info("${req.toDebugString()}");
  }
}

class _RootNode {
  RouteNode node;
}

class _RouteController extends Controller {
  _RouteController(this.specifications) {
    specifications.forEach((p) {
      p.controller = this;
    });
  }

  /// Route specifications for this controller.
  final List<RouteSpecification> specifications;

  @override
  Map<String, APIPath> documentPaths(APIDocumentContext components) {
    return specifications.fold(<String, APIPath>{}, (pathMap, spec) {
      final elements = spec.segments.map((rs) {
        if (rs.isLiteralMatcher) {
          return rs.literal;
        } else if (rs.isVariable) {
          return "{${rs.variableName}}";
        } else if (rs.isRemainingMatcher) {
          return "{path}";
        }
        throw StateError("unknown specification");
      }).join("/");
      final pathKey = "/$elements";

      final path = APIPath()
        ..parameters = spec.variableNames
            .map((pathVar) => APIParameter.path(pathVar))
            .toList();

      if (spec.segments.any((seg) => seg.isRemainingMatcher)) {
        path.parameters.add(APIParameter.path("path")
          ..description =
              "This path variable may contain slashes '/' and may be empty.");
      }

      path.operations =
          spec.controller.documentOperations(components, pathKey, path);

      pathMap[pathKey] = path;

      return pathMap;
    });
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}
