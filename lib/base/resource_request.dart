part of monadart;

/// Represents a single HTTP request.
///
/// Contains a standard library [HttpRequest], along with other values
/// to associate data with a request.
class ResourceRequest implements RequestHandlerResult {
  /// The internal [HttpRequest] of this [ResourceRequest].
  ///
  /// The standard library generated HTTP request object. This contains
  /// all of the request information provided by the client.
  final HttpRequest innerRequest;

  /// The response object of this [ResourceRequest].
  ///
  /// To respond to a request, this object must be written to. It is the same
  /// instance as the [request]'s response.
  HttpResponse get response => innerRequest.response;

  /// The path and any extracted variable parameters from the URI of this request.
  ///
  /// Typically set by a [Router] instance when the request has been piped through one,
  /// this property will contain a list of each path segment, a map of matched variables,
  /// and any remaining wildcard path. For example, if the path '/users/:id' and a the request URI path is '/users/1',
  /// path will have [segments] of ['users', '1'] and [variables] of {'id' : '1'}.
  ResourcePatternMatch path;

  /// Permission information associated with this request.
  ///
  /// When this request goes through an [Authenticator], this value will be set with
  /// permission information from the authenticator. Use this to determine client, resource owner
  /// or other properties of the authentication information in the request. This value will be
  /// null if no permission has been set.
  Permission permission;

  int id = new DateTime.now().millisecondsSinceEpoch;

  ResourceRequest(this.innerRequest) {}

  void respond(Response respObj) {
    new Logger("monadart").info("Request ($id) sending response $respObj.");

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

  String toString() {
    return "${this.innerRequest.uri} (${this.id})";
  }

  String toDebugString() {
    var builder = new StringBuffer();
    builder.writeln("${this.innerRequest.uri} (${this.id})");
    this.innerRequest.headers.forEach((name, values) {
      builder.write("$name $values,");
    });
    return builder.toString();
  }
}
