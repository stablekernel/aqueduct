part of monadart;

/// The unifying protocol for [ResourceRequest] and [Response] classes.
///
///
abstract class RequestHandlerResult {}

/// RequestHandlers respond to, modify or forward requests.
///
/// This class is intended to be extended. RequestHandlers are sent [ResourceRequest]s through
/// their [deliver] method, which in turn invokes [processRequest]. Subclasses
/// should implement [processRequest] to respond to, modify or forward requests.
/// In some cases, subclasses may also override [deliver].
class RequestHandler {
  Function _handler;

  /// The initializer for RequestHandlers.
  ///
  /// To use a closure-based RequestHandler, you may specify [requestHandler] for
  /// this instance. Otherwise, you may subclass [RequestHandler] and implement
  /// [processRequest] (or in rare cases, [deliver]) to handle request.
  RequestHandler({RequestHandlerResult requestHandler(ResourceRequest req): null}) {
    _handler = requestHandler;
  }

  /// The next [RequestHandler] to run if this one responds with [shouldContinue].
  ///
  /// Handlers may be chained together if they have the option not to respond to requests.
  /// If this handler returns a [ResourceRequest] from [processRequest], this [nextHandler]
  /// handler will run. Prefer using [then] to chain together handlers in a single statement.
  RequestHandler nextHandler;

  /// The next [RequestHandler] to run if this instance returns a [ResourceRequest].
  ///
  /// Handlers may be chained together if they have the option not to respond to requests.
  /// If this handler returns a [ResourceRequest] from [processRequest], this [nextHandler]
  /// handler will run. This method sets the [nextHandler] property] and returns [this]
  /// to allow chaining.
  RequestHandler then(RequestHandler next) {
    this.nextHandler = next;
    return this;
  }

  /// The mechanism for delivering a [ResourceRequest] to this handler for processing.
  ///
  /// This method is the entry point of a [ResourceRequest] into this [RequestHandler].
  /// By default, it invokes this handler's [processRequest] method and, if that method
  /// determines processing should continue with the [nextHandler] handler and a
  /// [nextHandler] handler exists, the request will be delivered to [nextHandler].
  ///
  /// An [ApplicationPipeline] should invoke this method on its initial handler
  /// in its [processRequest] method.
  ///
  /// Some [RequestHandler]s may override this method if they do not wish to
  /// use simple chaining. For example, the [Router] class] overrides this method
  /// to deliver the [ResourceRequest] to the appropriate route handler. If overriding this
  /// method, it is important that you always invoke subsequent handler's with [deliver]
  /// and not [processRequest].

  void deliver(ResourceRequest req) {
    processRequest(req)
        .then((result) {
          if (result is ResourceRequest && nextHandler != null) {
            nextHandler.deliver(req);
          } else if (result is Response) {
            req.respond(result as Response);
          }
        })
        .catchError((err) {
          if (err is HttpResponseException) {
            req.respond(err.response());
          } else {
            var st = null;
            try {
              throw new Exception("nonsense");
            } catch (_, stacktrace) {
              st = stacktrace;
            }
            req.respond(new Response.serverError(body: {"error" : "Unexpected exception in ${this.runtimeType}.", "stacktrace" : st.toString()}));
          }
        });
  }

  /// Overridden by subclasses to modify or respond to an incoming request.
  ///
  /// Subclasses override this method to provide their specific handling of a request. A [RequestHandler]
  /// should either modify or respond to the request.
  ///
  /// [RequestHandler]s should return a [Response] from this method if they responded to the request.
  /// If a [RequestHandler] does not respond to the request, but instead modifies it, this method must return the same [ResourceRequest].
  Future<RequestHandlerResult> processRequest(ResourceRequest req) async {
    if (_handler != null) {
      return _handler(req);
    }
    return req;
  }
}

class RequestHandlerGenerator<T> extends RequestHandler {
  @override
  void deliver(ResourceRequest req) {
    var handler = reflectClass(T).newInstance(new Symbol(""), []).reflectee
        as RequestHandler;
    handler.nextHandler = this.nextHandler;
    handler.deliver(req);
  }
}
