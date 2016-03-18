part of monadart;

abstract class MockServer {
  MockServer() {
    _queue = [];
    _nextEventCompleter = null;
  }

  List _queue;
  Completer _nextEventCompleter;

  Future open();
  Future close();

  void add(dynamic value) {
    if (_nextEventCompleter != null) {
      _nextEventCompleter.complete(value);
      _nextEventCompleter = null;
    } else {
      _queue.add(value);
    }
  }

  Future next() {
    if (_queue.isEmpty) {
      if (_nextEventCompleter == null) {
        _nextEventCompleter = new Completer();
      }

      return _nextEventCompleter.future;
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

  dynamic bodyAsJSON() {
    return JSON.decode(body);
  }
}

class MockHTTPServer extends MockServer {
  MockHTTPServer(this.port) : super();

  int port;
  HttpServer server;

  List<Response> responseQueue = [];

  void queueResponse(Response resp) {
    responseQueue.add(resp);
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

      if (responseQueue.length > 0) {
        var respObj = responseQueue.first;
        responseQueue.removeAt(0);

        req.response.statusCode = respObj.statusCode;

        if (respObj.headers != null) {
          respObj.headers.forEach((k, v) {
            req.response.headers.add(k, v);
          });
        }

        if (respObj.body != null) {
          req.response.write(respObj.body);
        }

        req.response.close();
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