part of aqueduct;

/// Indicates that an [HTTPController] method is triggered by an HTTP GET method.
///
/// Controller methods on [HTTPController]s that handle GET requests must be marked with this.
const HTTPMethod httpGet = const HTTPMethod("get");

/// Indicates that an [HTTPController] method is triggered by an HTTP PUT method.
///
/// Controller methods on [HTTPController]s that handle PUT requests must be marked with this.
const HTTPMethod httpPut = const HTTPMethod("put");

/// Indicates that an [HTTPController] method is triggered by an HTTP POST method.
///
/// Controller methods on [HTTPController]s that handle POST requests must be marked with this.
const HTTPMethod httpPost = const HTTPMethod("post");

/// Indicates that an [HTTPController] method is triggered by an HTTP DELETE method.
///
/// Controller methods on [HTTPController]s that handle DELETE requests must be marked with this.
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// Indicates that an [HTTPController] method is triggered by an HTTP PATCH method.
///
/// Controller methods on [HTTPController]s that handle PATCH requests must be marked with this.
const HTTPMethod httpPatch = const HTTPMethod("patch");

/// [HTTPController] method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HTTPController] 'responder' method for an HTTP request must be marked with an instance
/// of [HTTPMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HTTPMethod {
  /// Creates an instance of [HTTPMethod] that will case-insensitively match the [String] argument of an HTTP request.
  const HTTPMethod(this.method);

  /// The method that the marked request responder method corresponds to.
  ///
  /// Case-insensitive.
  final String method;
}
