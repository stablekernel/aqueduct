import 'dart:async';
import 'dart:mirrors';
import 'dart:io';

import 'package:logging/logging.dart';

import 'http.dart';
import '../db/db.dart';

/// The unifying protocol for [Request] and [Response] classes.
///
/// A [RequestController] must return an instance of this type from its [RequestController.processRequest] method.
abstract class RequestOrResponse {}

typedef FutureOr<RequestOrResponse> _RequestControllerListener(Request request);

/// Base type that processes [Request]s.
///
/// Instances of this type process requests by creating a [Response] or passing the [Request] to [nextController]. The [nextController]
/// is set at startup in [RequestSink.setupRouter] via [pipe], [generate], or [listen].
///
/// This class is intended to be subclassed. [RequestSink], [Router], [HTTPController] are all examples of this type.
/// Subclasses should implement [processRequest] to respond to, modify or forward requests.
class RequestController extends Object with APIDocumentable {
  /// Default constructor.
  RequestController();

  RequestController._withListener(this._listener);

  /// Returns a stacktrace and additional details about how the request's processing in the HTTP response.
  ///
  /// By default, this is false. During debugging, setting this to true can help debug Aqueduct applications
  /// from the HTTP client.
  static bool includeErrorDetailsInServerErrorResponses = false;

  /// Whether or not to allow uncaught exceptions escape request controllers.
  ///
  /// When this value is false - the default - all [RequestController] instances handle
  /// unexpected exceptions by catching and logging them, and then returning a 500 error.
  ///
  /// While running tests, it is useful to know where unexpected exceptions come from because
  /// they are an error in your code. By setting this value to true, all [RequestController]s
  /// will rethrow unexpected exceptions in addition to the base behavior. This allows the stack
  /// trace of the unexpected exception to appear in test results and halt the tests with failure.
  ///
  /// By default, this value is false. Do not set this value to true outside of tests.
  static bool letUncaughtExceptionsEscape = false;

  /// Receives requests that this controller does not respond to.
  ///
  /// Use [pipe], [generate] or [listen] to set this property.
  RequestController get nextController => _nextController;

  /// An instance of the 'aqueduct' logger.
  Logger get logger => new Logger("aqueduct");

  /// The CORS policy of this controller.
  CORSPolicy policy = new CORSPolicy();

  @override
  APIDocumentable get documentableChild => nextController;

  RequestController _nextController;
  _RequestControllerListener _listener;

  /// Sets the [nextController] that will receive a request after this one.
  ///
  /// If this instance returns a [Request] from [processRequest], that request is passed to [next]'s [receive] method.
  ///
  /// See [listen] for a variant of this method that takes a closure instead of an object.
  ///
  /// See [generate] for a variant of this method that creates a new instance for each request.
  RequestController pipe(RequestController next) {
    var typeMirror = reflect(next).type;
    if (_requestControllerTypeRequiresInstantion(typeMirror)) {
      throw new RequestControllerException(
          "'${typeMirror.reflectedType}' instances cannot be reused between requests. Rewrite as .generate(() => new ${typeMirror.reflectedType}())");
    }
    _nextController = next;

    return _nextController;
  }

  /// Sets the [nextController] that will receive a request after this one.
  ///
  /// If this instance returns a [Request] from [processRequest], that request is passed to the instance created by [instantiator]'s [receive] method.
  /// This method differs from [pipe] in that [instantiator] creates a new instance for each HTTP request, whereas [pipe] reuses
  /// the same controller for reach request.
  ///
  /// See [listen] for a variant of this method that takes a closure instead of an object.
  ///
  /// See [pipe] for a variant of this method that reuses the same object for each HTTP request.
  RequestController generate(RequestController instantiator()) {
    _nextController = new _RequestControllerGenerator(instantiator);
    return _nextController;
  }

  /// Sets the [nextController] that will receive a request after this one.
  ///
  /// If this instance returns a [Request] from [processRequest], that request is passed to [process].
  /// [process] is invoked in the same try-catch block as [processRequest].
  ///
  /// See [pipe] and [generate] for variants of this methods that objects instead of closures.
  RequestController listen(FutureOr<RequestOrResponse> process(Request request)) {
    _nextController = new RequestController._withListener(process);
    return _nextController;
  }

  bool _requestControllerTypeRequiresInstantion(ClassMirror mirror) {
    if (mirror.metadata.firstWhere((im) => im.reflectee is _RequiresInstantion,
            orElse: () => null) !=
        null) {
      return true;
    }
    if (mirror.isSubtypeOf(reflectType(RequestController))) {
      return _requestControllerTypeRequiresInstantion(mirror.superclass);
    }
    return false;
  }

  /// Delivers [req] to this instance to be processed.
  ///
  /// This method is the entry point of a [Request] into this [RequestController].
  /// By default, it invokes this controller's [processRequest] method within a try-catch block
  /// that guarantees an HTTP response will be sent for [Request].
  Future receive(Request req) async {
    if (req.isPreflightRequest) {
      return _handlePreflightRequest(req);
    }

    var result;
    try {
      result = await processRequest(req);
      if (result is Response) {
        await _sendResponse(req, result, includeCORSHeaders: true);
        logger.info(req.toDebugString());
        return null;
      }
    } catch (any, stacktrace) {
      var shouldRethrow = await handleError(req, any, stacktrace);
      if (letUncaughtExceptionsEscape && shouldRethrow) {
        rethrow;
      }

      return null;
    }

    return nextController?.receive(result);
  }

  /// Overridden by subclasses to modify or respond to an incoming request.
  ///
  /// Subclasses override this method to provide their specific handling of a request.
  ///
  /// If this method returns a [Response], it will be sent as the response for [req] and [req] will not be passed to any other controllers.
  ///
  /// If this method returns [req], [req] will be passed to [nextController].
  ///
  /// If this method returns null, [req] is not passed to any other controller and is not responded to. You must respond to [req]
  /// by through [Request.innerRequest].
  FutureOr<RequestOrResponse> processRequest(Request req) {
    if (_listener != null) {
      return _listener(req);
    }

    return req;
  }

  /// Executed prior to [Response] being sent.
  ///
  /// This method is used to post-process [response] just before it is sent. By default, does nothing.
  /// The [response] may be altered prior to being sent. This method will be executed for all requests,
  /// including server errors.
  void willSendResponse(Response response) {}

  /// Sends an HTTP response for a request that yields an exception or error.
  ///
  /// This method is automatically invoked by [receive] and should rarely be invoked otherwise.
  ///
  /// This method is invoked when an value is thrown inside an instance's [processRequest]. [request] is the [Request] being processed,
  /// [caughtValue] is the value that is thrown and [trace] is a [StackTrace] at the point of the throw.
  ///
  /// For unknown exceptions and errors, this method sends a 500 response for the request being processed. This ensures that any errors
  /// still yield a response to the HTTP client. If [includeErrorDetailsInServerErrorResponses] is true, the body of this
  /// method will contain the error and stacktrace as JSON data.
  ///
  /// If [caughtValue] is an [HTTPResponseException] or [QueryException], this method translates [caughtValue] and sends an appropriate
  /// HTTP response.
  ///
  /// For [HTTPResponseException]s, the response is created by [HTTPResponseException.response].
  ///
  /// For [QueryException]s, the response is one of the following:
  ///
  /// * 400: When the query is valid SQL but fails for any reason, except a unique constraint violation.
  /// * 409: When the query fails because of a unique constraint violation.
  /// * 500: When the query is invalid SQL.
  /// * 503: When the database cannot be reached.
  ///
  /// This method is invoked by [receive] and should not be invoked elsewhere. If a subclass overrides [receive], such as [Router],
  /// this method should be called to handle any errors.
  ///
  /// Note: [includeErrorDetailsInServerErrorResponses] is not evaluated when [caughtValue] is an [HTTPResponseException] or [QueryException], as
  /// these are normal control flows. There is one exception - if [QueryException.event] is [QueryExceptionEvent.internalFailure], this method
  /// will include the error and stacktrace. [QueryExceptionEvent.internalFailure] occurs when the [Query] is malformed.
  ///
  /// This method returns true if the error is unexpected, allowing [letUncaughtExceptionsEscape] to rethrow the exception during debugging.
  Future<bool> handleError(Request request, dynamic caughtValue, StackTrace trace) async {
    if (caughtValue is HTTPResponseException) {
      var response = caughtValue.response;
      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.info(
          "${request.toDebugString(includeHeaders: true)}");
    } else if (caughtValue is QueryException &&
        caughtValue.event != QueryExceptionEvent.internalFailure) {
      // Note that if the event is an internal failure, this code is skipped and the 500 handler is executed.
      var statusCode = 500;
      switch (caughtValue.event) {
        case QueryExceptionEvent.requestFailure:
          statusCode = 400;
          break;
        case QueryExceptionEvent.internalFailure:
          statusCode = 500;
          break;
        case QueryExceptionEvent.connectionFailure:
          statusCode = 503;
          break;
        case QueryExceptionEvent.conflict:
          statusCode = 409;
          break;
      }

      var response =
      new Response(statusCode, null, {"error": caughtValue.toString()});
      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.info(
          "${request.toDebugString(includeHeaders: true)}");
    } else if (caughtValue is HTTPStreamingException) {
      logger.severe(
          "${request.toDebugString(includeHeaders: true)}",
          caughtValue.underlyingException,
          caughtValue.trace);

      await request.response.close();

      return true;
    } else {
      var body;
      if (includeErrorDetailsInServerErrorResponses) {
        body = {
          "error": "${this.runtimeType}: $caughtValue.",
          "stacktrace": trace.toString()
        };
      }

      var response = new Response.serverError(body: body)
        ..contentType = ContentType.JSON;

      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.severe(
          "${request.toDebugString(includeHeaders: true)}",
          caughtValue,
          trace);

      return true;
    }

    return false;
  }

  Future _handlePreflightRequest(Request req) async {
    RequestController controllerToDictatePolicy;
    try {
      var lastControllerInChain = _lastRequestController();
      if (lastControllerInChain != this) {
        controllerToDictatePolicy = lastControllerInChain;
      } else {
        if (policy != null) {
          if (!policy.validatePreflightRequest(req.innerRequest)) {
            await _sendResponse(req, new Response.forbidden());
            logger.info(req.toDebugString(includeHeaders: true));
          } else {
            await _sendResponse(req, policy.preflightResponse(req));
            logger.info(req.toDebugString());
          }

          return null;
        } else {
          // If we don't have a policy, then a preflight request makes no sense.
          await _sendResponse(req, new Response.forbidden());
          logger.info(req.toDebugString(includeHeaders: true));
          return null;
        }
      }
    } catch (any, stacktrace) {
      return handleError(req, any, stacktrace);
    }

    return controllerToDictatePolicy?.receive(req);
  }

  Future _sendResponse(Request request, Response response,
      {bool includeCORSHeaders: false}) {
    if (includeCORSHeaders) {
      applyCORSHeadersIfNecessary(request, response);
    }
    willSendResponse(response);

    return request.respond(response);
  }

  RequestController _lastRequestController() {
    var controller = this;
    while (controller.nextController != null) {
      controller = controller.nextController;
    }
    return controller;
  }

  void applyCORSHeadersIfNecessary(Request req, Response resp) {
    if (req.isCORSRequest && !req.isPreflightRequest) {
      var lastPolicyController = _lastRequestController();
      var p = lastPolicyController.policy;
      if (p != null) {
        if (p.isRequestOriginAllowed(req.innerRequest)) {
          resp.headers.addAll(p.headersForRequest(req));
        }
      }
    }
  }
}

/// Metadata for a [RequestController] subclass that requires it must be instantiated for each request.
///
/// Requires that the [RequestController] must be created through [RequestController.generate].
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
  CORSPolicy _policyOverride;

  RequestController instantiate() {
    RequestController instance = generator();
    instance._nextController = this.nextController;
    if (_policyOverride != null) {
      instance.policy = _policyOverride;
    }
    return instance;
  }

  @override
  CORSPolicy get policy {
    return instantiate().policy;
  }

  @override
  set policy(CORSPolicy p) {
    _policyOverride = p;
  }

  @override
  Future receive(Request req) {
    return instantiate().receive(req);
  }

  @override
  APIDocument documentAPI(PackagePathResolver resolver) =>
      instantiate().documentAPI(resolver);

  @override
  List<APIPath> documentPaths(PackagePathResolver resolver) =>
      instantiate().documentPaths(resolver);

  @override
  List<APIOperation> documentOperations(PackagePathResolver resolver) =>
      instantiate().documentOperations(resolver);

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
          PackagePathResolver resolver) =>
      instantiate().documentSecuritySchemes(resolver);
}

/// Thrown when [RequestController] throws an exception.
///
///
class RequestControllerException implements Exception {
  RequestControllerException(this.message);

  String message;

  @override
  String toString() => "RequestControllerException: $message";
}
