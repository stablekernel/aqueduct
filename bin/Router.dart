import 'ResourcePattern.dart';
import 'dart:async';
import 'dart:io';


class Router {
  List<_ResourceRoute> routes;

  var _unhandledRequestHandler;
  void set unhandledRequestHandler(Function handler(HttpRequest req)) {
    _unhandledRequestHandler = handler;
  }

  Router() {
    routes = [];
    unhandledRequestHandler = _handleUnhandledRequest;
  }

  listener(HttpRequest req) {
    var matchResults = null;
    for (var route in routes) {
      var routeMatch = route.pattern.matchesInUri(req.uri);

      if(routeMatch != null) {
        var routedRequest = new RoutedHttpRequest(req, routeMatch);
        route.streamController.add(routedRequest);
        return;
      }
    }

    _unhandledRequestHandler(req);
  }

  _handleUnhandledRequest(HttpRequest req) {
    req.response.statusCode = 404;
    req.response.close();
  }

  Stream<RoutedHttpRequest> route(String pattern) {

    var controller = new StreamController<RoutedHttpRequest>();
    routes.add(new _ResourceRoute(new ResourcePattern(pattern), controller));

    return controller.stream;
  }
}

class RoutedHttpRequest {
  final HttpRequest request;
  final Map<String, String> pathValues;

  RoutedHttpRequest(this.request, this.pathValues);
}

class _ResourceRoute {
  final ResourcePattern pattern;
  final StreamController<RoutedHttpRequest> streamController;

  _ResourceRoute(this.pattern, this.streamController);

}