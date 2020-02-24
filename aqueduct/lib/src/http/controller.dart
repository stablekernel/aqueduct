import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/http/resource_controller_interfaces.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:logging/logging.dart';
import 'package:runtime/runtime.dart';

import 'http.dart';

typedef _ControllerGeneratorClosure = Controller Function();
typedef _Handler = FutureOr<RequestOrResponse> Function(Request request);

/// The unifying protocol for [Request] and [Response] classes.
///
/// A [Controller] must return an instance of this type from its [Controller.handle] method.
abstract class RequestOrResponse {}

/// An interface that [Controller] subclasses implement to generate a new controller for each request.
///
/// If a [Controller] implements this interface, a new [Controller] is created for each request. Controllers
/// must implement this interface if they declare setters or non-final properties, as those properties could
/// change during request handling.
///
/// A controller that implements this interface can store information that is not tied to the request
/// to be reused across each instance of the controller type by implementing [recycledState] and [restore].
/// Use these methods when a controller needs to construct runtime information that only needs to occur once
/// per controller type.
abstract class Recyclable<T> implements Controller {
  /// Returns state information that is reused across instances of this type.
  ///
  /// This method is called once when this instance is first created. It is passed
  /// to each new instance of this type via [restore].
  T get recycledState;

  /// Provides a new instance of this type with the [recycledState] of this type.
  ///
  /// Use this method it provide compiled runtime information to a new instance.
  void restore(T state);
}

/// An interface for linking controllers.
///
/// All [Controller]s implement this interface.
abstract class Linkable {
  /// See [Controller.link].
  Linkable link(Controller instantiator());

  /// See [Controller.linkFunction].
  Linkable linkFunction(FutureOr<RequestOrResponse> handle(Request request));
}

/// Base class for request handling objects.
///
/// A controller is a discrete processing unit for requests. These units are linked
/// together to form a series of steps that fully handle a request.
///
/// Subclasses must implement [handle] to respond to, modify or forward requests.
/// This class must be subclassed. [Router] and [ResourceController] are common subclasses.
abstract class Controller
    implements APIComponentDocumenter, APIOperationDocumenter, Linkable {
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
  Logger get logger => Logger("aqueduct");

  /// The CORS policy of this controller.
  CORSPolicy policy = CORSPolicy();

  Controller _nextController;

  /// Links a controller to the receiver to form a request channel.
  ///
  /// Establishes a channel containing the receiver and the controller returned by [instantiator]. If
  /// the receiver does not handle a request, the controller created by [instantiator] will get an opportunity to do so.
  ///
  /// [instantiator] is called immediately when invoking this function. If the returned [Controller] does not implement
  /// [Recyclable], this is the only time [instantiator] is called. The returned controller must only have properties that
  /// are marked as final.
  ///
  /// If the returned controller has properties that are not marked as final, it must implement [Recyclable].
  /// When a controller implements [Recyclable], [instantiator] is called for each new request that
  /// reaches this point of the channel. See [Recyclable] for more details.
  ///
  /// See [linkFunction] for a variant of this method that takes a closure instead of an object.
  @override
  Linkable link(Controller instantiator()) {
    final instance = instantiator();
    if (instance is Recyclable) {
      _nextController = _ControllerRecycler(instantiator, instance);
    } else {
      _nextController = instantiator();
    }

    return _nextController;
  }

  /// Links a function controller to the receiver to form a request channel.
  ///
  /// If the receiver does not respond to a request, [handle] receives the request next.
  ///
  /// See [link] for a variant of this method that takes an object instead of a closure.
  @override
  Linkable linkFunction(FutureOr<RequestOrResponse> handle(Request request)) {
    return _nextController = _FunctionController(handle);
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
  /// If you override this method you should call the superclass' implementation so that linked controllers invoke this same method.
  /// If you do not invoke the superclass' implementation, you must ensure that any linked controllers invoked this method through other means.
  void didAddToChannel() {
    _nextController?.didAddToChannel();
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

    Request next;
    try {
      try {
        final result = await handle(req);
        if (result is Response) {
          await _sendResponse(req, result, includeCORSHeaders: true);
          logger.info(req.toDebugString());
          return null;
        } else if (result is Request) {
          next = result;
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
      // ignore: unawaited_futures
      handleError(req, any, stacktrace);

      if (letUncaughtExceptionsEscape) {
        rethrow;
      }

      return null;
    }

    if (next == null) {
      return null;
    }

    return nextController?.receive(next);
  }

  /// The primary request handling method of this object.
  ///
  /// Subclasses implement this method to provide their request handling logic.
  ///
  /// If this method returns a [Response], it will be sent as the response for [request] linked controllers will not handle it.
  ///
  /// If this method returns [request], the linked controller handles the request.
  ///
  /// If this method returns null, [request] is not passed to any other controller and is not responded to. You must respond to [request]
  /// through [Request.raw].
  FutureOr<RequestOrResponse> handle(Request request);

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
  Future handleError(
      Request request, dynamic caughtValue, StackTrace trace) async {
    if (caughtValue is HTTPStreamingException) {
      logger.severe("${request.toDebugString(includeHeaders: true)}",
          caughtValue.underlyingException, caughtValue.trace);

      // ignore: unawaited_futures
      request.response.close().catchError((_) => null);

      return;
    }

    try {
      final body = includeErrorDetailsInServerErrorResponses
          ? {
              "controller": "$runtimeType",
              "error": "$caughtValue.",
              "stacktrace": trace?.toString()
            }
          : null;

      final response = Response.serverError(body: body)
        ..contentType = ContentType.json;

      await _sendResponse(request, response, includeCORSHeaders: true);

      logger.severe(
          "${request.toDebugString(includeHeaders: true)}", caughtValue, trace);
    } catch (e) {
      logger.severe("Failed to send response, draining request. Reason: $e");
      // ignore: unawaited_futures
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
  Map<String, APIPath> documentPaths(APIDocumentContext context) =>
      nextController?.documentPaths(context);

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    if (nextController == null) {
      return {};
    }

    return nextController?.documentOperations(context, route, path);
  }

  @override
  void documentComponents(APIDocumentContext context) =>
      nextController?.documentComponents(context);

  Future _handlePreflightRequest(Request req) async {
    Controller controllerToDictatePolicy;
    try {
      var lastControllerInChain = _lastController;
      if (lastControllerInChain != this) {
        controllerToDictatePolicy = lastControllerInChain;
      } else {
        if (policy != null) {
          if (!policy.validatePreflightRequest(req.raw)) {
            await _sendResponse(req, Response.forbidden());
            logger.info(req.toDebugString(includeHeaders: true));
          } else {
            await _sendResponse(req, policy.preflightResponse(req));
            logger.info(req.toDebugString());
          }

          return null;
        } else {
          // If we don't have a policy, then a preflight request makes no sense.
          await _sendResponse(req, Response.forbidden());
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
      {bool includeCORSHeaders = false}) {
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

@PreventCompilation()
class _ControllerRecycler<T> extends Controller {
  _ControllerRecycler(this.generator, Recyclable<T> instance) {
    recycleState = instance.recycledState;
    nextInstanceToReceive = instance;
  }

  _ControllerGeneratorClosure generator;
  CORSPolicy policyOverride;
  T recycleState;

  Recyclable<T> _nextInstanceToReceive;

  Recyclable<T> get nextInstanceToReceive => _nextInstanceToReceive;

  set nextInstanceToReceive(Recyclable<T> instance) {
    _nextInstanceToReceive = instance;
    instance.restore(recycleState);
    instance._nextController = nextController;
    if (policyOverride != null) {
      instance.policy = policyOverride;
    }
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
  Linkable link(Controller instantiator()) {
    final c = super.link(instantiator);
    nextInstanceToReceive._nextController = c as Controller;
    return c;
  }

  @override
  Linkable linkFunction(FutureOr<RequestOrResponse> handle(Request request)) {
    final c = super.linkFunction(handle);
    nextInstanceToReceive._nextController = c as Controller;
    return c;
  }

  @override
  Future receive(Request req) {
    final next = nextInstanceToReceive;
    nextInstanceToReceive = generator() as Recyclable<T>;
    return next.receive(req);
  }

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    throw StateError("_ControllerRecycler invoked handle. This is a bug.");
  }

  @override
  void didAddToChannel() {
    // don't call super, since nextInstanceToReceive's nextController is set to the same instance,
    // and it must call nextController.prepare
    nextInstanceToReceive.didAddToChannel();
  }

  @override
  void documentComponents(APIDocumentContext components) =>
      nextInstanceToReceive.documentComponents(components);

  @override
  Map<String, APIPath> documentPaths(APIDocumentContext components) =>
      nextInstanceToReceive.documentPaths(components);

  @override
  Map<String, APIOperation> documentOperations(
          APIDocumentContext components, String route, APIPath path) =>
      nextInstanceToReceive.documentOperations(components, route, path);
}

@PreventCompilation()
class _FunctionController extends Controller {
  _FunctionController(this._handler) : assert(_handler != null);

  final _Handler _handler;

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return _handler(request);
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    if (nextController == null) {
      return {};
    }

    return nextController?.documentOperations(context, route, path);
  }
}

abstract class ControllerRuntime {
  bool get isMutable;

  ResourceControllerRuntime get resourceController;
}