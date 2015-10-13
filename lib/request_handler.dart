part of monadart;

abstract class RequestHandler {
  void handleRequest(ResourceRequest req);
}

class RequestHandlerGenerator<T> implements RequestHandler {
  void handleRequest(ResourceRequest req) {
    var handler = reflectClass(T).newInstance(new Symbol(""), []).reflectee
        as RequestHandler;
    handler.handleRequest(req);
  }
}
