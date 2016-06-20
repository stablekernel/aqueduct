part of aqueduct;

/// The unifying protocol for [Request] and [Response] classes.
///
///
abstract class RequestHandlerResult {}

/// RequestHandlers respond to, modify or forward requests.
///
/// This class is intended to be extended. RequestHandlers are sent [Request]s through
/// their [deliver] method, which in turn invokes [processRequest]. Subclasses
/// should implement [processRequest] to respond to, modify or forward requests.
/// In some cases, subclasses may also override [deliver].
class RequestHandler implements APIDocumentable {
  Function _handler;

  CORSPolicy policy = new CORSPolicy();
  Logger get logger => new Logger("aqueduct");

  /// The initializer for RequestHandlers.
  ///
  /// To use a closure-based RequestHandler, you may specify [requestHandler] for
  /// this instance. Otherwise, you may subclass [RequestHandler] and implement
  /// [processRequest] (or in rare cases, [deliver]) to handle request.
  RequestHandler({RequestHandlerResult requestHandler(Request req): null}) {
    _handler = requestHandler;
  }

  /// The next [RequestHandler] to run if this one responds with [shouldContinue].
  ///
  /// Handlers may be chained together if they have the option not to respond to requests.
  /// If this handler returns a [Request] from [processRequest], this [nextHandler]
  /// handler will run. Prefer using [next] to chain together handlers in a single statement.
  RequestHandler nextHandler;

  /// The next [RequestHandler] to run if this instance returns a [Request].
  ///
  /// Handlers may be chained together if they have the option not to respond to requests.
  /// If this handler returns a [Request] from [processRequest], this [nextHandler]
  /// handler will run. This method sets the [nextHandler] property] and returns [this]
  /// to allow chaining. This parameter may be an instance of [RequestHandler] or a
  /// function that takes no arguments and returns a [RequestHandler]. In the latter instance,
  /// a new instance of the returned [RequestHandler] is created for each request. Otherwise,
  /// the same instance is used for each request. All [HTTPController]s and subclasses should
  /// be wrapped in a function that returns a new instance of the controller.
  RequestHandler next(dynamic n) {
    if (n is Function) {
      n = new _RequestHandlerGenerator(n);
    } else {
      var typeMirror = reflect(n).type;
      if (_requestHandlerTypeRequiresInstantion(typeMirror)) {
        throw new IsolateSupervisorException("RequestHandler ${typeMirror.reflectedType} instances cannot be reused. Rewrite as .next(() => new ${typeMirror.reflectedType}())");
      }
    }
    this.nextHandler = n;
    return n;
  }

  bool _requestHandlerTypeRequiresInstantion(ClassMirror mirror) {
    if (mirror.metadata.firstWhere((im) => im.reflectee is _RequiresInstantion, orElse: () => null) != null) {
      return true;
    }
    if (mirror.isSubtypeOf(reflectType(RequestHandler))) {
      return _requestHandlerTypeRequiresInstantion(mirror.superclass);
    }
    return false;
  }

  /// The mechanism for delivering a [Request] to this handler for processing.
  ///
  /// This method is the entry point of a [Request] into this [RequestHandler].
  /// By default, it invokes this handler's [processRequest] method and, if that method
  /// determines processing should continue with the [nextHandler] handler and a
  /// [nextHandler] handler exists, the request will be delivered to [nextHandler].
  ///
  /// An [ApplicationPipeline] invokes this method on its initial handler
  /// in its [processRequest] method.
  ///
  /// Some [RequestHandler]s may override this method if they do not wish to
  /// use simple chaining. For example, the [Router] class overrides this method
  /// to deliver the [Request] to the appropriate route handler. If overriding this
  /// method, it is important that you always invoke subsequent handler's with [deliver]
  /// and not [processRequest]. You must also ensure that CORS requests are handled properly,
  /// as this method does the heavy-lifting for handling CORS requests.
  Future deliver(Request req) async {
    try {
      if (isCORSRequest(req) && isPreflightRequest(req)) {
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
            req.respond(policy.preflightResponse(req));
            logger.info(req.toDebugString());
          }
          return;
        }
        // If we have no policy, then it isn't really a preflight request because we don't support CORS so let it fall thru.
      }

      var result = await processRequest(req);

      if (result is Request && nextHandler != null) {
        nextHandler.deliver(req);
      } else if (result is Response) {
        _applyCORSHeadersIfNecessary(req, result);
        req.respond(result as Response);
        logger.info(req.toDebugString());
      }
    } on HTTPResponseException catch (err) {
      var response = err.response();
      _applyCORSHeadersIfNecessary(req, response);
      req.respond(response);
      logger.info("${req.toDebugString(includeHeaders: true, includeBody: true)} ${err.message}");
    } catch (err, st) {
      var response = new Response.serverError(headers: {HttpHeaders.CONTENT_TYPE: ContentType.JSON}, body: {"error": "${this.runtimeType}: $err.", "stacktrace": st.toString()});
      _applyCORSHeadersIfNecessary(req, response);
      req.respond(response);
      logger.severe("${req.toDebugString(includeHeaders: true, includeBody: true)} $err $st");
    }
  }

  /// Overridden by subclasses to modify or respond to an incoming request.
  ///
  /// Subclasses override this method to provide their specific handling of a request. A [RequestHandler]
  /// should either modify or respond to the request.
  ///
  /// [RequestHandler]s should return a [Response] from this method if they responded to the request.
  /// If a [RequestHandler] does not respond to the request, but instead modifies it, this method must return the same [Request].
  Future<RequestHandlerResult> processRequest(Request req) async {
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

  void _applyCORSHeadersIfNecessary(Request req, Response resp) {
    if (isCORSRequest(req)) {
      var lastPolicyHandler = _lastRequestHandler();
      var p = lastPolicyHandler.policy;
      if (p != null) {
        if (p.isRequestOriginAllowed(req.innerRequest)) {
          resp.headers.addAll(p.headersForRequest(req));
        }
      }
    }
  }

  bool isCORSRequest(Request req) {
    return req.innerRequest.headers.value("origin") != null;
  }

  bool isPreflightRequest(Request req) {
    return req.innerRequest.method == "OPTIONS" && req.innerRequest.headers.value("access-control-request-method") != null;
  }

  List<APIDocumentItem> document(PackagePathResolver resolver) {
    if (nextHandler != null) {
      return nextHandler.document(resolver);
    }

    return [];
  }
}

/// Metadata for a [RequestHandler] subclass that indicates it must be instantiated for each request.
///
/// [RequestHandler]s may carry some state throughout the course of their handling of a request. If
/// that [RequestHandler] is reused for another request, some of that state may carry over. Therefore,
/// it is a better solution to instantiate the [RequestHandler] for each incoming request. Marking
/// a [RequestHandler] subclass with this flag will ensure that an exception is thrown if an instance
/// of [RequestHandler] is chained in a pipeline. These instances must be generated with a closure:
///
///       router.route("/path").then(() => new RequestHandlerSubclass());
const _RequiresInstantion cannotBeReused = const _RequiresInstantion();
class _RequiresInstantion {
  const _RequiresInstantion();
}

class _RequestHandlerGenerator extends RequestHandler {
  _RequestHandlerGenerator(RequestHandler generator()) {
    this.generator = generator;
  }

  Function generator;

  RequestHandler instantiate() {
    RequestHandler instance = generator();
    instance.nextHandler = this.nextHandler;
    if (_policy != null) {
      instance.policy = _policy;
    }
    return instance;
  }

  CORSPolicy _policy;
  CORSPolicy get policy {
    return instantiate().policy;
  }
  void set policy(CORSPolicy p) {
    _policy = p;
  }

  @override
  Future deliver(Request req) async {
    await instantiate().deliver(req);
  }

  @override
  List<APIDocumentItem> document(PackagePathResolver resolver) {
    return instantiate().document(resolver);
  }
}
