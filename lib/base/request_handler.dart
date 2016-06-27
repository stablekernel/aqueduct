part of aqueduct;

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
class RequestHandler implements APIDocumentable {
  Function _handler;

  Logger get logger => new Logger("aqueduct");

  CORSPolicy policy = new CORSPolicy();

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
    return next;
  }

  /// The mechanism for delivering a [ResourceRequest] to this handler for processing.
  ///
  /// This method is the entry point of a [ResourceRequest] into this [RequestHandler].
  /// By default, it invokes this handler's [processRequest] method and, if that method
  /// determines processing should continue with the [nextHandler] handler and a
  /// [nextHandler] handler exists, the request will be delivered to [nextHandler].
  ///
  /// An [ApplicationPipeline] invokes this method on its initial handler
  /// in its [processRequest] method.
  ///
  /// Some [RequestHandler]s may override this method if they do not wish to
  /// use simple chaining. For example, the [Router] class overrides this method
  /// to deliver the [ResourceRequest] to the appropriate route handler. If overriding this
  /// method, it is important that you always invoke subsequent handler's with [deliver]
  /// and not [processRequest].

  Future deliver(ResourceRequest req) async {
    try {
      if (isPreflightRequest(req)) {
        var handlerToDictatePolicy = _lastRequestHandler();
        if (handlerToDictatePolicy != this) {
          handlerToDictatePolicy.deliver(req);
          return;
        }

        if (policy != null) {
          if (!policy.validatePreflightRequest(req.innerRequest)) {
            req.respond(new Response.forbidden());
            logger.info(req.toDebugString(includeHeaders: true));
          } else {
            // If we are the last on the chain, we can OK the preflight request, otherwise, we let the next handler deal with it.
            if (nextHandler == null) {
              req.respond(policy.preflightResponse(req));
              logger.info(req.toDebugString());
            } else {
              nextHandler.deliver(req);
            }
          }
          return;
        }
        // If we have no policy, then it isn't really a preflight request because we don't support CORS so let it fall thru.
      }

      var result = await processRequest(req);

      if (result is ResourceRequest && nextHandler != null) {
        nextHandler.deliver(req);
      } else if (result is Response) {
        _applyCORSHeadersIfNecessary(req, result);
        req.respond(result as Response);
        logger.info(req.toDebugString());
      }
    } on HttpResponseException catch (e) {
      var response = e.response();
      _applyCORSHeadersIfNecessary(req, response);
      req.respond(response);
      logger.info(req.toDebugString(includeHeaders: true, includeBody: true));
    } catch (err, st) {
      var response = new Response.serverError(headers: {HttpHeaders.CONTENT_TYPE: "application/json"}, body: JSON.encode({"error": "${this.runtimeType}: $err.", "stacktrace": st.toString()}));
      _applyCORSHeadersIfNecessary(req, response);
      req.respond(response);
      logger.severe(req.toDebugString(includeHeaders: true, includeBody: true));
      logger.severe("${st}");
    }
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

  RequestHandler _lastRequestHandler() {
    var handler = this;
    while (handler.nextHandler != null) {
      handler = handler.nextHandler;
    }
    return handler;
  }

  void _applyCORSHeadersIfNecessary(ResourceRequest req, Response resp) {
    if (isCORSRequest(req)) {
      var lastPolicyHandler = _lastRequestHandler();
      var p = lastPolicyHandler.policy;
      if (p != null) {
        resp.headers.addAll(p.headersForRequest(req));
      }
    }
  }

  bool isCORSRequest(ResourceRequest req) {
    return req.innerRequest.headers.value("origin") != null;
  }

  bool isPreflightRequest(ResourceRequest req) {
    if (req.innerRequest.headers.value("origin") != null) {
      return req.innerRequest.method == "OPTIONS";
    }
    return false;
  }

  List<APIDocumentItem> document(PackagePathResolver resolver) {
    if (nextHandler != null) {
      return nextHandler.document(resolver);
    }

    return [];
  }
}

class RequestHandlerGenerator<T extends RequestHandler> extends RequestHandler {
  RequestHandlerGenerator({List<dynamic> arguments: const []}) {
    this.arguments = arguments;
  }

  List<dynamic> arguments;
  CORSPolicy get policy {
    return instantiate().policy;
  }
  void set policy(CORSPolicy p) {}

  T instantiate() {
    var handler = reflectClass(T).newInstance(new Symbol(""), arguments).reflectee as RequestHandler;
    handler.nextHandler = this.nextHandler;
    return handler;
  }

  @override
  Future deliver(ResourceRequest req) async {
    logger.finest("Generating handler $T with arguments $arguments.");
    T handler = instantiate();
    await handler.deliver(req);
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    return instantiate().document(resolver);
  }

}
