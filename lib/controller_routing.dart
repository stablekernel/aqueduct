part of monadart;

/// A 'GET' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle GET requests must be annotated with this.
const HttpMethod httpGet = const HttpMethod("get");

/// A 'PUT' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle PUT requests must be annotated with this.
const HttpMethod httpPut = const HttpMethod("put");

/// A 'POST' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle POST requests must be annotated with this.
const HttpMethod httpPost = const HttpMethod("post");

/// A 'DELETE' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle DELETE requests must be annotated with this.
const HttpMethod httpDelete = const HttpMethod("delete");

/// A 'PATCH' HttpMethod annotation.
///
/// Handler methods on [HttpController]s that handle PATCH requests must be annotated with this.
const HttpMethod httpPatch = const HttpMethod("patch");

/// Resource controller handler method metadata for indicating the HTTP method the controller method corresponds to.
///
/// Each [HttpController] method that is the entry point for an HTTP request must be decorated with an instance
/// of [HttpMethod]. See [httpGet], [httpPut], [httpPost] and [httpDelete] for concrete examples.
class HttpMethod {
  /// The method that the annotated request handler method corresponds to.
  ///
  /// Case-insensitive.
  final String method;

  final List<String> _parameters;

  const HttpMethod(this.method) : this._parameters = null;

  HttpMethod._fromMethod(HttpMethod m, List<String> parameters)
      : this.method = m.method,
        this._parameters = parameters;

  /// Returns whether or not this [HttpMethod] matches a [ResourceRequest].
  bool matchesRequest(ResourceRequest req) {
    if (req.request.method.toLowerCase() != this.method.toLowerCase()) {
      return false;
    }

    if (req.path.variables == null) {
      if (this._parameters.length == 0) {
        return true;
      }
      return false;
    }

    if (req.path.variables.length != this._parameters.length) {
      return false;
    }

    for (var id in this._parameters) {
      if (req.path.variables[id] == null) {
        return false;
      }
    }

    return true;
  }
}
