import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';

/// This class is used as a utility for testing.
///
/// Concrete implementations - like [MockHTTPServer] - are used to validate messages send to remote servers during testing. This allows
/// your tests to verify any messages sent as a side-effect of an endpoint. You should be sure to close instances of this class during tearDown functions.
abstract class MockServer<T> {
  List<T> _queue = [];
  List<Completer<T>> _completerQueue = [];

  /// Whether or not there are any messages that have been sent to this instance but have yet to be read.
  bool get isEmpty => _queue.isEmpty;

  /// Concrete implementations override this method to open an event listener.
  Future open();

  /// Concrete implementations override this method to close an event listener.
  Future close();

  /// Adds an event to this server.
  void add(T value) {
    if (_completerQueue.isNotEmpty) {
      _completerQueue.removeAt(0).complete(value);
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
      final c = Completer<T>();
      _completerQueue.add(c);
      return c.future;
    }

    return Future.value(_queue.removeAt(0));
  }
}

/// This class is used as a 'mock' implementation of another HTTP server.
///
/// Create instances of these types during testing to simulate responses for HTTP requests your application makes to another server.
/// All requests your application makes to another server will be sent to this object. Your tests can then verify the
/// correct request was sent and your application's behavior can be validated against the possible responses from the other server.
///
/// An instance of this type listens on 'localhost' on [port]. Your application should use configuration values to provide the base URL and port
/// of another server. During testing, your application should use the base URL 'http://localhost:<port>' and instantiate an mock HTTP
/// server with that port.
///
/// By default, an instance of this type returns a 503 error response, indicating that the service can't be reached. Different
/// responses can be returned via [defaultResponse], [queueResponse], [queueHandler], and [queueOutage].
///
/// Example usages:
///         test("POST /nest/pair associates account with Nest service", () async {
///           var nestMockServer = MockHTTPServer(7777);
///           await nestMockServer.open();
///
///           // Expect that POST /nest/pair sends an HTTP request to Nest server.
///           var response = await client.request("/nest/pair", ...).post();
///           expect(response, ...);
///
///           // Verify the path of the HTTP request sent to Nest server.
///           var requestSentToNest = await nestMockServer.next();
///           expect(requestSentToNest.path.segments[1, response["id"]);
///
///           await nestMockServer.close();
///         });
///
class MockHTTPServer extends MockServer<Request> {
  MockHTTPServer(this.port) : super();

  /// The port to listen on.
  int port;

  /// The underlying [HttpServer] listening for requests.
  HttpServer server;

  /// The response to be returned if there are no queued responses
  ///
  /// The default response is a 503 with a JSON Error body
  Response defaultResponse = Response(503, {}, {"error": "No queued requests"});

  /// The delay to be used for responses where a delay is not set
  ///
  /// The default delay is null which is no delay. If set, all subsequent
  /// queued responses delayed by this amount, unless they have their own delay.
  /// Changes to this value do not affect responses already in the queue.
  Duration defaultDelay;

  /// The number of currently queued responses
  int get queuedResponseCount => _responseQueue.length;

  final List<_MockServerResponse> _responseQueue = [];

  /// Enqueues a response for the next request.
  ///
  /// Adds a static response to the response queue. Each request removes the earliest enqueued
  /// response before sending it. Optionally includes a [delay] before sending
  /// the response to simulate long-running tasks or network issues.
  void queueResponse(Response resp, {Duration delay}) {
    _responseQueue
        .add(_MockServerResponse(object: resp, delay: delay ?? defaultDelay));
  }

  /// Enqueues a function that creates a response for the next request.
  ///
  /// Adds a dynamic response handler to the response queue. Each request removes the earliest enqueued
  /// response before sending it. When [handler] is encountered in the queue, it is called and the response
  /// it returns is sent back to the client.
  ///
  /// Optionally includes a [delay] before sending the response to simulate long-running tasks or network issues.
  void queueHandler(Response handler(Request request), {Duration delay}) {
    _responseQueue.add(
        _MockServerResponse(handler: handler, delay: delay ?? defaultDelay));
  }

  /// Enqueues an outage; the next request will not receive a response.
  ///
  /// Adds an outage event to the response queue. Each request removes the earliest enqueued response
  /// before sending it. When an outage is encountered, no response is sent. Specify number of outage events
  /// with [count].
  void queueOutage({int count = 1}) {
    _responseQueue.add(_MockServerResponse(outageCount: count));
  }

  /// Begins listening for HTTP requests on [port].
  @override
  Future open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.map((req) => Request(req)).listen((req) async {
      add(req);

      await req.body.decode();

      final response = await _dequeue(req);
      if (response != null) {
        await req.respond(response);
      }
    });
  }

  /// Shuts down the server listening for HTTP requests.
  @override
  Future close() {
    return server?.close();
  }

  Future<Response> _dequeue(Request incoming) async {
    if (_responseQueue.isEmpty) {
      if (defaultDelay != null) {
        await Future.delayed(defaultDelay);
      }
      return defaultResponse;
    }

    final resp = _responseQueue.first;
    if (resp.outageCount > 0) {
      resp.outageCount -= 1;

      if (resp.outageCount == 0) {
        _responseQueue.removeAt(0);
      }

      if (defaultDelay != null) {
        await Future.delayed(defaultDelay);
      }

      return null;
    }

    _responseQueue.removeAt(0);
    return resp.respond(incoming);
  }
}

typedef _MockRequestHandler = Response Function(Request request);

class _MockServerResponse {
  _MockServerResponse(
      {this.object, this.handler, this.delay, this.outageCount = 0});

  final Duration delay;

  final Response object;
  final _MockRequestHandler handler;
  int outageCount;

  Future<Response> respond(Request req) async {
    if (delay != null) {
      await Future.delayed(delay);
    }

    if (handler != null) {
      return handler(req);
    } else if (object != null) {
      return object;
    }

    return null;
  }
}
