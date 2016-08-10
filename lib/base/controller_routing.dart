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

abstract class _HTTPParameter {
  const _HTTPParameter(String externalName) : this.required(externalName);
  const _HTTPParameter.unnamed({ this.isRequired: false }) : externalName = null;
  const _HTTPParameter.required(this.externalName) : isRequired = true;
  const _HTTPParameter.optional(this.externalName) : isRequired = false;

  final String externalName;
  final bool isRequired;
}

const HTTPHeader httpHeader = const HTTPHeader.unnamed();

/// Metadata indicating a parameter to a controller's method should be set from
/// the HTTP header indicated by the [header] field.
class HTTPHeader extends _HTTPParameter {
  const HTTPHeader(String header) : super.required(header);
  const HTTPHeader.unnamed({ bool isRequired: false }) : super.unnamed(isRequired: isRequired);
  const HTTPHeader.required(String header) : super.required(header);
  const HTTPHeader.optional(String header) : super.optional(header);
}

const HTTPQuery httpQuery = const HTTPQuery.unnamed();

class HTTPQuery extends _HTTPParameter {
  const HTTPQuery(String key) : this.required(key);
  const HTTPQuery.unnamed({ bool isRequired: false }) : super.unnamed(isRequired: isRequired);
  const HTTPQuery.required(String key) : super.required(key);
  const HTTPQuery.optional(String key) : super.optional(key);
}