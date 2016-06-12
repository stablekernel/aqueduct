part of aqueduct;

abstract class MockServer {
  List _queue = [];
  List<Completer> _completerQueue = [];

  bool get isEmpty => _queue.isEmpty;

  Future open();
  Future close();

  void add(dynamic value) {
    if (_completerQueue.length > 0) {
      var nextEventCompleter = _completerQueue.removeAt(0);
      nextEventCompleter.complete(value);
    } else {
      _queue.add(value);
    }
  }

  void clear() {
    _queue = [];
    _completerQueue = [];
  }

  Future next() {
    if (_queue.isEmpty) {
      var c = new Completer();
      _completerQueue.add(c);
      return c.future;
    }

    var val = _queue.removeAt(0);
    return new Future.value(val);
  }
}

class MockHTTPRequest {
  String method;
  String path;
  String body;
  Map<String, dynamic> queryParameters;
  Map<String, dynamic> headers;

  dynamic get jsonBody {
    return JSON.decode(body);
  }
}

class MockHTTPServer extends MockServer {
  static final int _mockConnectionFailureStatusCode = -1;
  static final Response mockConnectionFailureResponse = new Response(_mockConnectionFailureStatusCode , {}, null);

  MockHTTPServer(this.port) : super();

  int port;
  HttpServer server;

  List<Response> responseQueue = [];

  void queueResponse(Response resp) {
    responseQueue.add(resp);
  }

  @override
  Future<MockHTTPRequest> next() async {
    return super.next();
  }

  @override
  Future open() async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, port);
    server.listen((HttpRequest req) async {
      var mockReq = new MockHTTPRequest()
        ..method = req.method
        ..path = req.uri.path
        ..queryParameters = req.uri.queryParameters;

      mockReq.headers = {};
      req.headers.forEach((name, values) {
        mockReq.headers[name] = values.join(",");
      });

      if (req.contentLength > 0) {
        mockReq.body = new String.fromCharCodes(await req.first);
      }

      add(mockReq);

      if (responseQueue.length > 0) {
        var respObj = responseQueue.first;
        responseQueue.removeAt(0);

        if (respObj.statusCode == _mockConnectionFailureStatusCode) {
          // We let this one die by not responding.
          return;
        }

        var wrappedReq = new ResourceRequest(req);
        wrappedReq.respond(respObj);
      } else {
        req.response.statusCode = 200;
        req.response.close();
      }
    });
  }

  Future close() async {
    await server?.close();
  }
}