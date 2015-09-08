part of monadart;

/// Represents a single HTTP request.
///
/// Contains a standard library [HttpRequest], along with other values
/// to associate data with a request.
class ResourceRequest {

  /// The internal [HttpRequest] of this [ResourceRequest].
  ///
  /// The standard library generated HTTP request object. This contains
  /// all of the request information provided by the client.
  final HttpRequest request;

  /// The response object of this [ResourceRequest].
  ///
  /// To respond to a request, this object must be written to. It is the same
  /// instance as the [request]'s response.
  HttpResponse get response => request.response;

  /// The path and any extracted variable parameters from the URI of this request.
  ///
  /// Typically set by a [Router] instance when the request has been piped through one,
  /// this property will contain a list of each path segment, a map of matched variables,
  /// and any remaining wildcard path. For example, if the path '/users/:id' and a the request URI path is '/users/1',
  /// path will have [segments] of ['users', '1'] and [variables] of {'id' : '1'}.
  ResourcePatternMatch path;

  /// Optional data for members of a pipeline to attach to a request for later members to utilize.
  ///
  /// This is purely contextual to the application. An example is pipeline that adds a database adapter
  /// to the request so that the handling [HttpController] has access to it.
  Map<dynamic, dynamic> context = new Map();

  ResourceRequest(this.request) {

  }

  void respond(Response respObj) {
    response.statusCode = respObj.statusCode;

    if (respObj.headers != null) {
      respObj.headers.forEach((k, v) {
        response.headers.add(k, v);
      });
    }

    if (respObj.body != null) {
      response.write(respObj.body);
    }

    response.close();
  }
}