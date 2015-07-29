part of monadart;

class Router {
  List<_ResourceRoute> routes;

  var _unhandledRequestHandler;
  void set unhandledRequestHandler(Function handler(Request req)) {
    _unhandledRequestHandler = handler;
  }

  Router() {
    routes = [];
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  Stream<Request> addRoute(String pattern) {

    var controller = new StreamController<Request>();
    routes.add(new _ResourceRoute(new ResourcePattern(pattern), controller));

    return controller.stream;
  }

  listener(Request req) {
    for (var route in routes) {
      var routeMatch = route.pattern.matchesInUri(req.request.uri);

      if(routeMatch != null) {
        req.addValue("route", routeMatch);
        route.streamController.add(req);
        return;
      }
    }

    _unhandledRequestHandler(req);
  }

  _handleUnhandledRequest(Request req) {
    req.request.response.statusCode = 404;
    req.request.response.close();
  }
}

class _ResourceRoute {
  final ResourcePattern pattern;
  final StreamController<Request> streamController;

  _ResourceRoute(this.pattern, this.streamController);

}