part of aqueduct;

/// 'GET' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle GET requests must be marked with this.
const HTTPMethod httpGet = const HTTPMethod("get");

/// 'PUT' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle PUT requests must be marked with this.
const HTTPMethod httpPut = const HTTPMethod("put");

/// 'POST' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle POST requests must be marked with this.
const HTTPMethod httpPost = const HTTPMethod("post");

/// 'DELETE' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle DELETE requests must be marked with this.
const HTTPMethod httpDelete = const HTTPMethod("delete");

/// 'PATCH' HttpMethod metadata.
///
/// Handler methods on [HTTPController]s that handle PATCH requests must be marked with this.
const HTTPMethod httpPatch = const HTTPMethod("patch");

/// Resource controller handler method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HTTPController] handler method for an HTTP request must be marked with an instance
/// of [HTTPMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HTTPMethod {
  /// Creates an instance of [HTTPMethod] that will case-insensitively match the [String] argument of an HTTP request.
  const HTTPMethod(this.method);

  /// The method that the marked request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;
}

/// Metadata indicating a parameter to a controller's method should be set from
/// the HTTP header indicated by the [header] field.
class HTTPHeader {
  const HTTPHeader(String header) : this.required(header);
  const HTTPHeader.required(this.header) : isRequired = true;
  const HTTPHeader.optional(this.header) : isRequired = false;

  final String header;
  final bool isRequired;
}

class HTTPQuery {
  const HTTPQuery(String key) : this.required(key);
  const HTTPQuery.required(this.key) : isRequired = true;
  const HTTPQuery.optional(this.key) : isRequired = false;

  final String key;
  final bool isRequired;
}