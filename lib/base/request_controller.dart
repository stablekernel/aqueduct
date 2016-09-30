part of aqueduct;

/// The unifying protocol for [Request] and [Response] classes.
///
///
abstract class RequestControllerEvent {}

/// [RequestController]s respond to, modify or forward requests.
///
/// This class is intended to be extended. [RequestController]s are sent [Request]s through
/// their [receive] method, which in turn invokes [processRequest]. Subclasses
/// should implement [processRequest] to respond to, modify or forward requests.
/// In some cases, subclasses may also override [receive].
class RequestController extends Object with APIDocumentable {
  static bool includeErrorDetailsInServerErrorResponses = false;

  Function _listener;
  RequestController nextController;

  @override
  APIDocumentable get documentableChild => nextController;

  Logger get logger => new Logger("aqueduct");

  CORSPolicy get policy => _policy;
  CORSPolicy _policy = new CORSPolicy();
  void set policy(CORSPolicy p) {
    _policy = p;
  }

  /// The next [RequestController] to run if this instance returns a [Request].
  ///
  /// Controllers  may be chained together if they have the option not to respond to requests.
  /// If this controller returns a [Request] from [processRequest], this [nextController]
  /// will run. This method sets the [nextController] property] and returns [this]
  /// to allow chaining. This parameter may be an instance of [RequestController] or a
  /// function that takes no arguments and returns a [RequestController]. In the latter instance,
  /// a new instance of the returned [RequestController] is created for each request. Otherwise,
  /// the same instance is used for each request. All [HTTPController]s and subclasses should
  /// be wrapped in a function that returns a new instance of the controller.
  RequestController pipe(RequestController n) {
    var typeMirror = reflect(n).type;
    if (_requestControllerTypeRequiresInstantion(typeMirror)) {
      throw new IsolateSupervisorException("RequestController subclass ${typeMirror.reflectedType} instances cannot be reused. Rewrite as .generate(() => new ${typeMirror.reflectedType}())");
    }
    this.nextController = n;

    return this.nextController;
  }

  RequestController generate(RequestController generatorFunction()) {
    this.nextController = new _RequestControllerGenerator(generatorFunction);
    return this.nextController;
  }

  RequestController listen(Future<RequestControllerEvent> requestControllerFunction(Request request)) {
    var controller = new RequestController()
        .._listener = requestControllerFunction;
    this.nextController = controller;
    return controller;
  }

  bool _requestControllerTypeRequiresInstantion(ClassMirror mirror) {
    if (mirror.metadata.firstWhere((im) => im.reflectee is _RequiresInstantion, orElse: () => null) != null) {
      return true;
    }
    if (mirror.isSubtypeOf(reflectType(RequestController))) {
      return _requestControllerTypeRequiresInstantion(mirror.superclass);
    }
    return false;
  }

  /// The mechanism for delivering a [Request] to this controller for processing.
  ///
  /// This method is the entry point of a [Request] into this [RequestController].
  /// By default, it invokes this controller's [processRequest] method and, if that method
  /// determines processing should continue with the [nextController] and a
  /// [nextController] exists, the request will be delivered to [nextController].
  ///
  /// An [RequestSink] invokes this method on its initial controller
  /// in its [processRequest] method.
  ///
  /// Some [RequestController]s may override this method if they do not wish to
  /// use simple chaining. For example, the [Router] class overrides this method
  /// to deliver the [Request] to the appropriate route controller. If overriding this
  /// method, it is important that you always invoke subsequent controller's with [receive]
  /// and not [processRequest]. You must also ensure that CORS requests are handled properly,
  /// as this method does the heavy-lifting for handling CORS requests.
  Future receive(Request req) async {
    try {
      if (isCORSRequest(req) && isPreflightRequest(req)) {
        var controllerToDictatePolicy = _lastRequestController();
        if (controllerToDictatePolicy != this) {
          controllerToDictatePolicy.receive(req);
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

      if (result is Request && nextController != null) {
        nextController.receive(req);
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
  /// Subclasses override this method to provide their specific handling of a request. A [RequestController]
  /// should either modify or respond to the request.
  ///
  /// [RequestController]s should return a [Response] from this method if they responded to the request.
  /// If a [RequestController] does not respond to the request, but instead modifies it, this method must return the same [Request].
  Future<RequestControllerEvent> processRequest(Request req) async {
    if (_listener != null) {
      return await _listener(req);
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

  RequestController _lastRequestController() {
    var controller = this;
    while (controller.nextController != null) {
      controller = controller.nextController;
    }
    return controller;
  }

  void _applyCORSHeadersIfNecessary(Request req, Response resp) {
    if (isCORSRequest(req)) {
      var lastPolicyController = _lastRequestController();
      var p = lastPolicyController.policy;
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

/// Metadata for a [RequestController] subclass that indicates it must be instantiated for each request.
///
/// [RequestController]s may carry some state throughout the course of their handling of a request. If
/// that [RequestController] is reused for another request, some of that state may carry over. Therefore,
/// it is a better solution to instantiate the [RequestController] for each incoming request. Marking
/// a [RequestController] subclass with this flag will ensure that an exception is thrown if an instance
/// of [RequestController] is chained in a [RequestSink]. These instances must be generated with a closure:
///
///       router.route("/path").generate(() => new RequestControllerSubclass());
const _RequiresInstantion cannotBeReused = const _RequiresInstantion();
class _RequiresInstantion {
  const _RequiresInstantion();
}

class _RequestControllerGenerator extends RequestController {
  _RequestControllerGenerator(RequestController generator()) {
    this.generator = generator;
  }

  Function generator;
  CORSPolicy _policyOverride = null;

  RequestController instantiate() {
    RequestController instance = generator();
    instance.nextController = this.nextController;
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
  Future receive(Request req) async {
    await instantiate().receive(req);
  }

  @override
  APIDocument documentAPI(PackagePathResolver resolver) => instantiate().documentAPI(resolver);

  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) => instantiate().documentPaths(resolver);

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) => instantiate().documentOperations(resolver);

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) => instantiate().documentSecuritySchemes(resolver);

  @override
  APIRequestBody documentRequestBodyForOperation(APIOperation operation) => instantiate().documentRequestBodyForOperation(operation);
}
