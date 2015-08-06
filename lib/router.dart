part of monadart;

class Router {
  List<_ResourceRoute> routes;

  var _unhandledRequestHandler;
  void set unhandledRequestHandler(void handler(ResourceRequest req)) {
    _unhandledRequestHandler = handler;
  }

  Router() {
    routes = [];
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  Stream<ResourceRequest> addRoute(String pattern) {
    var streamController = new StreamController<ResourceRequest>();
    routes.add(new _ResourceRoute(new ResourcePattern(pattern), streamController));

    return streamController.stream;
  }

  void listener(ResourceRequest req) {
    for (var route in routes) {
      var routeMatch = route.pattern.matchesInUri(req.request.uri);

      if(routeMatch != null) {
        req.pathParameters = routeMatch;

        route.streamController.add(req);

        return;
      }
    }

    _unhandledRequestHandler(req);
  }

  void _handleUnhandledRequest(ResourceRequest req) {
    req.response.statusCode = HttpStatus.NOT_FOUND;
    req.response.close();
  }
}

class _ResourceRoute {
  final ResourcePattern pattern;
  final StreamController<ResourceRequest> streamController;

  _ResourceRoute(this.pattern, this.streamController);
}

class RouterException implements Exception {
  final String message;

  RouterException(this.message);
}