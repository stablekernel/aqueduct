part of aqueduct;

/// This class is used as a utility for testing.
///
/// Concrete implementations - like [MockHTTPServer] - are used to validate messages send to remote servers during testing. This allows
/// your tests to verify any messages sent as a side-effect of an endpoint. You should be sure to close instances of this class during tearDown functions.
abstract class MockServer {
  List _queue = [];
  List<Completer> _completerQueue = [];

  /// Whether or not there are any messages that have been sent to this instance but have yet to be read.
  bool get isEmpty => _queue.isEmpty;

  /// Concrete implementations override this method to open an event listener.
  Future open();

  /// Concrete implementations override this method to close an event listener.
  Future close();

  /// Adds an event to this server.
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

  /// Returns an event that has been added to this server.
  ///
  /// This method will return the first element in the first-in-first-out queue of events
  /// that have been added to this instance. If no events are available, this [Future] will
  /// complete when the next event is added.
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

/// The 'event' type for [MockHTTPServer].
///
/// Instances of this type will represent HTTP requests that have been sent to an [MockHTTPServer].
class MockHTTPRequest {
  /// The method of the HTTP request.
  String method;

  /// The path of the HTTP request.
  String path;

  /// The undecoded body of the HTTP request.
  String body;

  /// The query parameters of the HTTP request.
  Map<String, dynamic> queryParameters;

  /// The headers of the HTTP request.
  Map<String, dynamic> headers;

  /// The body of the HTTP request decoded as JSON.
  dynamic get jsonBody {
    return JSON.decode(body);
  }
}

/// This class is used as a utility for testing.
///
/// Concrete implementations - like [MockHTTPServer] - are used to validate messages send to remote servers during testing. This allows
/// your tests to verify any messages sent as a side-effect of an endpoint. For example, an application that has an endpoint
/// that allows its user to associate their Nest account would use this class during testing. Instances of this class listen
/// on localhost. You should be sure to close instances of this class during tearDown functions.
///
/// By default, any request made to an instance of this type will be responded to with a 200 and no HTTP body.
/// You may add responses to instances of this class with [queueResponse]. They will be returned in the order
/// they were provided in.
///
/// Example usages:
///         test("Associate Nest account", () async {
///           var nestMockServer = new MockHTTPServer(nestPort);
///           await nestMockServer.open();
///
///           // Expect that POST /nest/pair sends an HTTP request to Nest server.
///           var response = await client.authenticatedRequest("/nest/pair", ...).post();
///           expect(response, ...);
///
///           // Verify the path of the HTTP request sent to Nest server.
///           var requestSentToNest = await nestMockServer.next();
///           expect(requestSentToNest .path, contains("${response["id"]}));
///
///           await nestMockServer.close();
///         });
///
///         test("Associate Nest account returns 503 when Nest is unreachable", () async {
///           var nestMockServer = new MockHTTPServer(nestPort);
///
///           await nestMockServer.open();
///           nestMockServer.queueResponse(MockHTTPServer.mockConnectionFailureResponse);
///           var response = await client.authenticatedRequest("/nest/pair", ...).post();
///           expect(response, hasStatus(503));
///
///           await nestMockServer.close();
///         });
class MockHTTPServer extends MockServer {
  static final int _mockConnectionFailureStatusCode = -1;

  /// Used to simulate a failed request.
  ///
  /// Pass this value to [queueResponse] to simulate a 'no response' failure on the next request made to this instance.
  /// The next request made to this instance will simply not be responded to.
  /// This is useful in debugging for determining how your code responds to not being able to reach a third party server.
  static final Response mockConnectionFailureResponse =
      new Response(_mockConnectionFailureStatusCode, {}, null);

  MockHTTPServer(this.port) : super();

  /// The port to listen on.
  int port;

  /// The underlying [HttpServer] listening for requests.
  HttpServer server;

  /// The queue of responses that will be returned when HTTP requests are made against this instance.
  ///
  /// See [queueResponse].
  List<Response> responseQueue = [];

  /// Adds an HTTP response to the list of responses to be returned.
  ///
  /// A queued response will be returned for the next HTTP request made to this instance and will then be removed.
  /// You may queue up as many responses as you like and they will be returned in order.
  void queueResponse(Response resp) {
    responseQueue.add(resp);
  }

  /// Retrieves the least recent, unread [MockHTTPRequest] from this instance.
  ///
  /// If no more requests are sent to this instance, the returned [Future] will not be completed.
  @override
  Future<MockHTTPRequest> next() async {
    return super.next();
  }

  /// Begins listening for HTTP requests on [port].
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
          return null;
        }

        var wrappedReq = new Request(req);
        wrappedReq.respond(respObj);
      } else {
        req.response.statusCode = 200;
        req.response.close();
      }
    });
  }

  /// Shuts down the server listening for HTTP requests.
  Future close() async {
    await server?.close();
  }
}
