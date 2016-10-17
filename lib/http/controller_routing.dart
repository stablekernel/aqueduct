part of aqueduct;

/// 'GET' HttpMethod metadata.
///
/// Controller methods on [HTTPController]s that handle GET requests must be marked with this.
const HTTPMethod httpGet = const HTTPMethod("get");

/// 'PUT' HttpMethod metadata.
///
/// Controller methods on [HTTPController]s that handle PUT requests must be marked with this.
const HTTPMethod httpPut = const HTTPMethod("put");

/// 'POST' HttpMethod metadata.
///
/// Controller methods on [HTTPController]s that handle POST requests must be marked with this.
const HTTPMethod httpPost = const HTTPMethod("post");

/// 'DELETE' HttpMethod metadata.
///
/// Controller methods on [HTTPController]s that handle DELETE requests must be marked with this.
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// 'PATCH' HttpMethod metadata.
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
