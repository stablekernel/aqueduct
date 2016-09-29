part of aqueduct;

/// Represents the information in an HTTP response.
///
/// This object can be used to write an HTTP response and contains conveniences
/// for creating these objects.
class Response implements RequestControllerEvent {
  /// An object representing the body of the [Response], which will be encoded when used to [Request.respond].
  ///
  /// This is typically a map or list of maps that will be encoded to JSON. If the [body] was previously set with a [Serializable] object
  /// or a list of [Serializable] objects, this property will be the already serialized (but not encoded) body.
  dynamic get body => _body;

  /// Sets the unencoded response body.
  ///
  /// This may be any value that can be encoded into an HTTP response body. If this value is a [Serializable] or a [List] of [Serializable],
  /// each instance of [Serializable] will transformed via its [Serializable.asSerializable] method before being set.
  void set body(dynamic initialResponseBody) {
      var serializedBody = null;
      if (initialResponseBody is Serializable) {
        serializedBody = initialResponseBody.asSerializable();
      } else if (initialResponseBody is List) {
        serializedBody = initialResponseBody.map((value) {
          if (value is Serializable) {
            return value.asSerializable();
          } else {
            return value;
          }
        }).toList();
      }

    _body = serializedBody ?? initialResponseBody;
  }
  dynamic _body;

  /// Map of headers to send in this response.
  ///
  /// Where the key is the Header name and value is the Header value.
  Map<String, dynamic> headers;

  /// The HTTP status code of this response.
  int statusCode;

  /// The default constructor.
  ///
  /// There exist convenience constructors for common response status codes
  /// and you should prefer to use those.
  Response(int statusCode, Map<String, dynamic> headers, dynamic body) {
    this.body = body;
    this.headers = headers;
    this.statusCode = statusCode;

    if (this.headers == null) {
      this.headers = {};
    }
  }

  /// Represents a 200 response.
  Response.ok(dynamic body, {Map<String, dynamic> headers}) : this(HttpStatus.OK, headers, body);

  /// Represents a 201 response.
  ///
  /// The [location] is a URI that is added as the Location header.
  Response.created(String location, {dynamic body, Map<String, dynamic> headers}) {
    this.headers = headers;
    this.body = body;
    this.statusCode = HttpStatus.CREATED;

    if (this.headers == null) {
      this.headers = {HttpHeaders.LOCATION: location};
    } else {
      this.headers[HttpHeaders.LOCATION] = location;
    }
  }

  /// Represents a 202 response.
  Response.accepted({Map<String, dynamic> headers}) : this(HttpStatus.ACCEPTED, headers, null);

  /// Represents a 400 response.
  Response.badRequest({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.BAD_REQUEST, headers, body);

  /// Represents a 401 response.
  Response.unauthorized({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.UNAUTHORIZED, headers, body);

  /// Represents a 403 response.
  Response.forbidden({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.FORBIDDEN, headers, body);

  /// Represents a 404 response.
  Response.notFound({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.NOT_FOUND, headers, body);

  /// Represents a 409 response.
  Response.conflict({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.CONFLICT, headers, body);

  /// Represents a 410 response.
  Response.gone({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.GONE, headers, body);

  /// Represents a 500 response.
  Response.serverError({Map<String, dynamic> headers, dynamic body}) : this(HttpStatus.INTERNAL_SERVER_ERROR, headers, body);

  String toString() {
    return "$statusCode $headers";
  }
}
