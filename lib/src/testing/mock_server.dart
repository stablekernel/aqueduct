import 'dart:async';
import 'dart:io';
import '../http/request.dart';
import '../http/response.dart';

/// This class is used as a utility for testing.
///
/// Concrete implementations - like [MockHTTPServer] - are used to validate messages send to remote servers during testing. This allows
/// your tests to verify any messages sent as a side-effect of an endpoint. You should be sure to close instances of this class during tearDown functions.
abstract class MockServer<T> {
  List _queue = [];
  List<Completer<T>> _completerQueue = [];

  /// Whether or not there are any messages that have been sent to this instance but have yet to be read.
  bool get isEmpty => _queue.isEmpty;

  /// Concrete implementations override this method to open an event listener.
  Future open();

  /// Concrete implementations override this method to close an event listener.
  Future close();

  /// Adds an event to this server.
  void add(T value) {
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
  Future<T> next() {
    if (_queue.isEmpty) {
      var c = new Completer<T>();
      _completerQueue.add(c);
      return c.future;
    }

    var val = _queue.removeAt(0);
    return new Future.value(val);
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
class MockHTTPServer extends MockServer<Request> {
  MockHTTPServer(this.port) : super();

  /// The port to listen on.
  int port;

  /// The underlying [HttpServer] listening for requests.
  HttpServer server;

  /// The response to be returned if there are no queued responses
  ///
  /// The default response is a 503 with a JSON Error body
  Response defaultResponse = new Response(503, {}, {"error": "No queued requests"});

  /// The delay to be used for responses where a delay is not set
  ///
  /// The default delay is null which is no delay
  Duration defaultDelay;

  /// The number of currently queued responses
  int get queuedResponseCount => _responseQueue.length;

  List<_MockServerResponse> _responseQueue = [];

  /// Adds an HTTP response to the list of responses to be returned.
  ///
  /// A queued response will be returned for the next HTTP request made to this instance and will then be removed.
  /// You may queue up as many responses as you like and they will be returned in order.
  /// If a delay is set in this method it will take precedence over [defaultDelay]. If delay isn't set or is explicitly set to null, [defaultDelay] will be used.
  void queueResponse(Response resp, {Duration delay}) {
    _responseQueue.add(new _MockServerResponse(object: resp, delay: delay ?? defaultDelay));
  }

  void queueHandler(Response handler(Request request), {Duration delay}) {
    _responseQueue.add(new _MockServerResponse(handler: handler, delay: delay ?? defaultDelay));
  }

  void queueOutage({int count: 1}) {
    _responseQueue.add(new _MockServerResponse(outageCount: count));
  }

  /// Begins listening for HTTP requests on [port].
  @override
  Future open() async {
    server = await HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, port);
    server.map((req) => new Request(req)).listen((req) async {
      add(req);

      await req.body.decodedData;

      final response = await _dequeue(req);
      if (response != null) {
        req.respond(response);
      }
    });
  }

  /// Shuts down the server listening for HTTP requests.
  @override
  Future close() {
    return server?.close();
  }

  Future<Response> _dequeue(Request incoming) async {
    if (_responseQueue.length == 0) {
      if (defaultDelay != null) {
        await new Future.delayed(defaultDelay);
      }
      return defaultResponse;
    }

    final resp = _responseQueue.first;
    if (resp.outageCount > 0) {
      resp.outageCount --;
      if (resp.outageCount == 0) {
        _responseQueue.removeAt(0);
      }

      return null;
    }
    
    return  _responseQueue.removeAt(0).respond(incoming);
  }
}

typedef Response _MockRequestHandler(Request request);

class _MockServerResponse {
  _MockServerResponse({this.object, this.handler, this.delay, this.outageCount: 0});

  final Duration delay;

  final Response object;
  final _MockRequestHandler handler;
  int outageCount;

  Future<Response> respond(Request req) async {
    if (delay != null) {
      await new Future.delayed(delay);
    }

    if (handler != null) {
      return handler(req);
    } else if (object != null) {
      return object;
    }

    return null;
  }
}
