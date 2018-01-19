import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

import 'http.dart';

/// The unifying protocol for [Request] and [Response] classes.
///
/// A [Controller] must return an instance of this type from its [Controller.handle] method.
abstract class RequestOrResponse {}

typedef FutureOr<RequestOrResponse> _Handler(Request request);

/// Controllers handle requests by either responding, or taking some action and passing the request to another controller.
///
/// A controller is a discrete processing unit for requests. These units are composed
/// together to form a series of steps that fully handle a request. This composability allows for reuse
/// of common tasks (like verifying an Authorization header) that can be inserted as a step for many different requests.
///
/// This class is intended to be subclassed. [ApplicationChannel], [Router], [RESTController] are all examples of this type.
/// Subclasses should implement [handle] to respond to, modify or forward requests.
class Controller extends Object with APIOperationDocumenter implements APIComponentDocumenter {
  /// Default constructor.
  ///
  /// For subclasses, override [handle] and do not provide [handler].
  ///
  /// For controllers that are simple, provide a [handler] or use [linkFunction].
  Controller([FutureOr<RequestOrResponse> handler(Request request)]) : _handler = handler;

  /// Returns a stacktrace and additional details about how the request's processing in the HTTP response.
  ///
  /// By default, this is false. During debugging, setting this to true can help debug Aqueduct applications
  /// from the HTTP client.
  static bool includeErrorDetailsInServerErrorResponses = false;

  /// Whether or not to allow uncaught exceptions escape request controllers.
  ///
  /// When this value is false - the default - all [Controller] instances handle
  /// unexpected exceptions by catching and logging them, and then returning a 500 error.
  ///
  /// While running tests, it is useful to know where unexpected exceptions come from because
  /// they are an error in your code. By setting this value to true, all [Controller]s
  /// will rethrow unexpected exceptions in addition to the base behavior. This allows the stack
  /// trace of the unexpected exception to appear in test results and halt the tests with failure.
  ///
  /// By default, this value is false. Do not set this value to true outside of tests.
  static bool letUncaughtExceptionsEscape = false;

  /// Receives requests that this controller does not respond to.
  ///
  /// This value is set by [link] or [linkFunction].
  Controller get nextController => _nextController;

  /// An instance of the 'aqueduct' logger.
  Logger get logger => new Logger("aqueduct");

  /// The CORS policy of this controller.
  CORSPolicy policy = new CORSPolicy();

  Controller _nextController;
  final _Handler _handler;

  /// Links a controller to the receiver.
  ///
  /// If the receiver does not respond to a request, the controller created by [instantiator] receives the request next.
  ///
  /// See [linkFunction] for a variant of this method that takes a closure instead of an object.
  Controller link(Controller instantiator()) {
    _nextController = new _ControllerGenerator(instantiator);
    return _nextController;
  }

  /// Links a function controller to the receiver.
  ///
  /// If the receiver does not respond to a request, [handle] receives the request next.
  ///
  /// See [link] for a variant of this method that takes an object instead of a closure.
  Controller linkFunction(FutureOr<RequestOrResponse> handle(Request request)) {
    _nextController = new Controller(handle);
    return _nextController;
  }

  /// Lifecycle callback, invoked after added to channel, but before any requests are served.
  ///
  /// Subclasses override this method to provide final, one-time initialization after it has been added to a channel,
  /// but before any requests are served. This is useful for performing any caching or optimizations for this instance.
  /// For example, [Router] overrides this method to optimize its list of routes into a more efficient data structure.
  ///
  /// This method is invoked immediately after [ApplicationChannel.entryPoint] is completes, for each
  /// instance in the channel created by [ApplicationChannel.entryPoint]. This method will only be called once per instance.
  ///
  /// Controllers added to the channel via [link] may use this method, but any values this method stores
  /// must be stored in a static structure, not the instance itself, since that instance will only be used to handle one request
  /// before it is garbage collected.
  ///
  /// If you override this method, you must call the superclass' implementation.
  void prepare() {
    _nextController?.prepare();
  }

  /// Delivers [req] to this instance to be processed.
  ///
  /// This method is the entry point of a [Request] into this [Controller].
  /// By default, it invokes this controller's [handle] method within a try-catch block
  /// that guarantees an HTTP response will be sent for [Request].
  Future receive(Request req) async {
    if (req.isPreflightRequest) {
      return _handlePreflightRequest(req);
    }

    var result;
    try {
      try {
        result = await handle(req);
        if (result is Response) {
          await _sendResponse(req, result, includeCORSHeaders: true);
          logger.info(req.toDebugString());
          return null;
        }
      } on Response catch (response) {
        await _sendResponse(req, response, includeCORSHeaders: true);
        logger.info(req.toDebugString());
        return null;
      } on HandlerException catch (e) {
        await _sendResponse(req, e.response, includeCORSHeaders: true);
        logger.info(req.toDebugString());
        return null;
      }
    } catch (any, stacktrace) {
      handleError(req, any, stacktrace);

      if (letUncaughtExceptionsEscape) {
        rethrow;
      }

      return null;
    }

    if (result == null) {
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
  /// through [Request.raw].
  FutureOr<RequestOrResponse> handle(Request req) {
    if (_handler != null) {
      return _handler(req);
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
  /// When this controller encounters an exception or error while handling [request], this method is called to send the response.
  /// By default, it attempts to send a 500 Server Error response and logs the error and stack trace to [logger].
  ///
  /// Note: If [caughtValue]'s implements [HandlerException], this method is not called.
  ///
  /// If you override this method, it must not throw.
  Future handleError(Request request, dynamic caughtValue, StackTrace trace) async {
    if (caughtValue is HTTPStreamingException) {
      logger.severe(
          "${request.toDebugString(includeHeaders: true)}", caughtValue.underlyingException, caughtValue.trace);

      request.response.close().catchError((_) => null);

      return;
    }

    try {
      final body = includeErrorDetailsInServerErrorResponses
          ? {"controller": "$runtimeType", "error": "$caughtValue.", "stacktrace": trace?.toString()}
          : null;

      final response = new Response.serverError(body: body)..contentType = ContentType.JSON;

      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.severe("${request.toDebugString(includeHeaders: true)}", caughtValue, trace);
    } catch (e) {
      logger.severe("Failed to send response, draining request. Reason: $e");
      request.raw.drain().catchError((_) => null);
    }
  }

  void applyCORSHeadersIfNecessary(Request req, Response resp) {
    if (req.isCORSRequest && !req.isPreflightRequest) {
      var lastPolicyController = _lastController;
      var p = lastPolicyController.policy;
      if (p != null) {
        if (p.isRequestOriginAllowed(req.raw)) {
          resp.headers.addAll(p.headersForRequest(req));
        }
      }
    }
  }

  @override
  Map<String, APIPath> documentPaths(APIDocumentContext context) => nextController?.documentPaths(context);

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext context, APIPath path) {
    if (nextController == null) {
      if (_handler == null) {
        throw new APIException(
            "Invalid documenter '${runtimeType}'. Reached end of controller chain and found no operations. Path has summary '${path
                .summary}'.");
      }
      return {};
    }

    return nextController?.documentOperations(context, path);
  }

  @override
  void documentComponents(APIDocumentContext context) => nextController?.documentComponents(context);

  Future _handlePreflightRequest(Request req) async {
    Controller controllerToDictatePolicy;
    try {
      var lastControllerInChain = _lastController;
      if (lastControllerInChain != this) {
        controllerToDictatePolicy = lastControllerInChain;
      } else {
        if (policy != null) {
          if (!policy.validatePreflightRequest(req.raw)) {
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

  Future _sendResponse(Request request, Response response, {bool includeCORSHeaders: false}) {
    if (includeCORSHeaders) {
      applyCORSHeadersIfNecessary(request, response);
    }
    willSendResponse(response);

    return request.respond(response);
  }

  Controller get _lastController {
    var controller = this;
    while (controller.nextController != null) {
      controller = controller.nextController;
    }
    return controller;
  }
}

/// Thrown when [Controller] throws an exception.
///
///
class ControllerException implements Exception {
  ControllerException(this.message);

  String message;

  @override
  String toString() => "ControllerException: $message";
}

typedef Controller _ControllerGeneratorClosure();

class _ControllerGenerator extends Controller {
  _ControllerGenerator(this.generator) {
    nextInstanceToReceive = instantiate();
  }

  _ControllerGeneratorClosure generator;
  CORSPolicy policyOverride;
  Controller nextInstanceToReceive;

  Controller instantiate() {
    Controller instance = generator();
    instance._nextController = nextController;
    if (policyOverride != null) {
      instance.policy = policyOverride;
    }
    return instance;
  }

  @override
  CORSPolicy get policy {
    return nextInstanceToReceive.policy;
  }

  @override
  set policy(CORSPolicy p) {
    policyOverride = p;
  }

  @override
  Controller link(Controller instantiator()) {
    final c = super.link(instantiator);
    nextInstanceToReceive._nextController = c;
    return c;
  }

  @override
  Controller linkFunction(FutureOr<RequestOrResponse> handle(Request request)) {
    final c = super.linkFunction(handle);
    nextInstanceToReceive._nextController = c;
    return c;
  }

  @override
  Future receive(Request req) {
    final next = nextInstanceToReceive;
    nextInstanceToReceive = instantiate();
    return next.receive(req);
  }

  @override
  void prepare() {
    // don't call super, since nextInstanceToReceive's nextController is set to the same instance,
    // and it must call nextController.prepare
    nextInstanceToReceive.prepare();
  }

  @override
  void documentComponents(APIDocumentContext components) => nextInstanceToReceive.documentComponents(components);

  @override
  Map<String, APIPath> documentPaths(APIDocumentContext components) => nextInstanceToReceive.documentPaths(components);

  @override
  Map<String, APIOperation> documentOperations(APIDocumentContext components, APIPath path) =>
      nextInstanceToReceive.documentOperations(components, path);
}
