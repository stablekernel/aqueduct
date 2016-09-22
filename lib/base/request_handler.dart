part of aqueduct;

typedef RequestHandler _RequestHandlerGeneratorFunction();

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
class RequestHandler extends Object with APIDocumentable {
  static bool includeErrorDetailsInServerErrorResponses = false;

  Function _handler;

  @override
  APIDocumentable get documentableChild => nextHandler;

  Logger get logger => new Logger("aqueduct");

  CORSPolicy get policy => _policy;
  CORSPolicy _policy = new CORSPolicy();
  void set policy(CORSPolicy p) {
    _policy = p;
  }

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
    if (n is _RequestHandlerGeneratorFunction) {
      this.nextHandler = new _RequestHandlerGenerator(n);
    } else {
      var typeMirror = reflect(n).type;
      if (_requestHandlerTypeRequiresInstantion(typeMirror)) {
        throw new IsolateSupervisorException("RequestHandler ${typeMirror.reflectedType} instances cannot be reused. Rewrite as .next(() => new ${typeMirror.reflectedType}())");
      }
      this.nextHandler = n;
    }

    return this.nextHandler;
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
        req.respond(result);

        logger.info(req.toDebugString());
      }
    } catch (any, stacktrace) {
      _handleError(req, any, stacktrace);
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

  void _handleError(Request request, dynamic caughtValue, StackTrace trace) {
    try {
      if (caughtValue is HTTPResponseException) {
        var response = caughtValue.response;
        _applyCORSHeadersIfNecessary(request, response);
        request.respond(response);

        logger.info("${request.toDebugString(includeHeaders: true, includeBody: true)}");
      } else if (caughtValue is QueryException && caughtValue.event != QueryExceptionEvent.internalFailure) {
        // Note that if the event is an internal failure, this code is skipped and the 500 handler is executed.
        var statusCode = 500;
        switch(caughtValue.event) {
          case QueryExceptionEvent.requestFailure: statusCode = 400; break;
          case QueryExceptionEvent.internalFailure: statusCode = 500; break;
          case QueryExceptionEvent.connectionFailure: statusCode = 503; break;
          case QueryExceptionEvent.conflict: statusCode = 409; break;
        }

        var response = new Response(statusCode, null, {"error" : caughtValue.toString()});
        _applyCORSHeadersIfNecessary(request, response);
        request.respond(response);

        logger.info("${request.toDebugString(includeHeaders: true, includeBody: true)}");
      } else {
        var body = null;
        if (includeErrorDetailsInServerErrorResponses) {
          body = {
            "error": "${this.runtimeType}: $caughtValue.",
            "stacktrace": trace.toString()
          };
        }

        var response = new Response.serverError(headers: {
          HttpHeaders.CONTENT_TYPE : ContentType.JSON
        }, body: body);

        _applyCORSHeadersIfNecessary(request, response);
        request.respond(response);

        logger.severe("${request.toDebugString(includeHeaders: true, includeBody: true)}", caughtValue, trace);
        }
    } catch (_) {}
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
  _RequestHandlerGenerator(_RequestHandlerGeneratorFunction generator) {
    this.generator = generator;
  }

  Function generator;
  CORSPolicy _policyOverride = null;

  RequestHandler instantiate() {
    RequestHandler instance = generator();
    instance.nextHandler = this.nextHandler;
    if (_policyOverride != null) {
      instance.policy = _policyOverride;
    }
    return instance;
  }

  CORSPolicy get policy {
    return instantiate().policy;
  }
  void set policy(CORSPolicy p) {
    _policyOverride = p;
  }

  @override
  Future deliver(Request req) async {
    await instantiate().deliver(req);
  }

  @override
  APIDocument documentAPI(PackagePathResolver resolver) => instantiate().documentAPI(resolver);

  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) => instantiate().documentPaths(resolver);

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) => instantiate().documentOperations(resolver);

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) => instantiate().documentSecuritySchemes(resolver);
}
