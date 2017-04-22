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

/// [RequestController]s respond to, modify or forward HTTP requests.
///
/// This class is intended to be extended. [RequestController]s are sent [Request]s through
/// their [receive] method, which in turn invokes [processRequest]. Subclasses
/// should implement [processRequest] to respond to, modify or forward requests.
/// In some cases, subclasses may also override [receive].
///
/// A request controller wraps the processing of a request in a try-catch block. If a request controller finishes processing a request
/// and does not respond to it, the [Request] is passed to the next [RequestController]. The next [RequestController] is defined
/// by methods such as [pipe], [generate], and [listen].
class RequestController extends Object with APIDocumentable {
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

  Function _listener;
  RequestController nextController;

  @override
  APIDocumentable get documentableChild => nextController;

  Logger get logger => new Logger("aqueduct");

  /// The CORS policy of this controller.
  CORSPolicy get policy => _policy;
  CORSPolicy _policy = new CORSPolicy();
  void set policy(CORSPolicy p) {
    _policy = p;
  }

  /// The next [RequestController] to pass a [Request] to if this instance returns a [Request] from [processRequest].
  ///
  /// Request controllers are chained together to form a pipeline that a request travels through to be responded to.
  /// This method adds an instance of some [RequestController] to a chain. A [RequestController] added to a chain
  /// in this way must not have any properties that change depending on the request, as many [Request]s will
  /// travel through the same instance in an asynchronous way.
  ///
  /// This method returns a [RequestController] that further [RequestController]s can be chained to.
  ///
  /// See also [generate] and [listen].
  RequestController pipe(RequestController n) {
    var typeMirror = reflect(n).type;
    if (_requestControllerTypeRequiresInstantion(typeMirror)) {
      throw new RequestControllerException(
          "RequestController subclass ${typeMirror.reflectedType} instances cannot be reused. Rewrite as .generate(() => new ${typeMirror.reflectedType}())");
    }
    this.nextController = n;

    return this.nextController;
  }

  /// A function that instantiates a [RequestController] to pass a [Request] to if this instance returns a [Request] from [processRequest].
  ///
  /// Request controllers are chained together to form a pipeline that a request travels through to be responded to.
  /// When this instance returns a [Request] from [processRequest], [generatorFunction] is called to instantiate
  /// a [RequestController]. The [Request] is then sent to the new [RequestController]. [RequestController]s
  /// that have properties that change depending on the incoming [Request] - like [HTTPController] - must be [generate]d
  /// for each [Request]. This avoids having a [RequestController]s properties change during the processing of a request due
  /// to asynchronous behavior.
  ///
  /// This method returns a [RequestController] that further [RequestController]s can be chained to.
  ///
  /// See also [pipe] and [listen].
  RequestController generate(RequestController generatorFunction()) {
    this.nextController = new _RequestControllerGenerator(generatorFunction);
    return this.nextController;
  }

  /// A closure that responds to or forwards a [Request].
  ///
  /// If this instance does not respond to a request, this closure is invoked, passing in the [Request] being processed.
  /// This is the barebones handler for [RequestController].
  ///
  /// This closure must return a [Request] or [Response].
  ///
  /// This method returns a [RequestController] that further [RequestController]s can be chained to.
  ///
  /// See also [generate] and [pipe].
  RequestController listen(
      Future<RequestOrResponse> requestControllerFunction(
          Request request)) {
    var controller = new RequestController()
      .._listener = requestControllerFunction;
    this.nextController = controller;
    return controller;
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

  /// The mechanism for delivering a [Request] to this controller for processing.
  ///
  /// This method is the entry point of a [Request] into this [RequestController].
  /// By default, it invokes this controller's [processRequest] method and, if that method
  /// determines processing should continue to the [nextController] and a
  /// [nextController] exists, the request will be delivered to [nextController].
  ///
  /// An [RequestSink] invokes this method on its initial controller
  /// in its [processRequest] method.
  ///
  /// Some [RequestController]s may override this method if they do not wish to
  /// use simple chaining. For example, the [Router] class overrides this method
  /// to deliver the [Request] to the appropriate [RouteController]. If overriding this
  /// method, it is important that you always invoke subsequent controller's with [receive]
  /// and not [processRequest]. You must also ensure that CORS requests are handled properly,
  /// as this method does the heavy-lifting for handling CORS requests.
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
  /// Subclasses override this method to provide their specific handling of a request. A [RequestController]
  /// should either modify or respond to the request. For concrete subclasses of [RequestController] - like [HTTPController] -
  /// this method has already been implemented.
  ///
  /// [RequestController]s should return a [Response] from this method if they responded to the request.
  /// If a [RequestController] does not respond to the request, but instead modifies it, this method must return the same [Request].
  Future<RequestOrResponse> processRequest(Request req) {
    if (_listener != null) {
      return _listener(req);
    }

    return new Future.microtask(() => req);
  }

  /// Executed prior to [Response] being sent.
  ///
  /// This method is used to post-process [response] just before it is sent. By default, does nothing.
  /// The [response] may be altered prior to being sent. This method will be executed for all requests,
  /// including server errors.
  void willSendResponse(Response response) {}

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

  Future<bool> handleError(Request request, dynamic caughtValue, StackTrace trace) async {
    if (caughtValue is HTTPResponseException) {
      var response = caughtValue.response;
      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.info(
          "${request.toDebugString(includeHeaders: true, includeBody: true)}");
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
          "${request.toDebugString(includeHeaders: true, includeBody: true)}");
    } else {
      var body = null;
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
          "${request.toDebugString(includeHeaders: true, includeBody: true)}",
          caughtValue,
          trace);

      return true;
    }

    return false;
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

  String toString() => "RequestControllerException: $message";
}
