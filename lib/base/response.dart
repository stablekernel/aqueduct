part of monadart;

/// Represents the information in an HTTP response.
///
/// This object can be used to write an HTTP response and contains conveniences
/// for creating these objects.
class Response implements RequestHandlerResult {
  /// An object representing the body of the [Response], which will be encoded later.
  ///
  /// This is typically a map that will be encoded to JSON.
  dynamic body;

  ///
  Map<String, String> headers;

  /// The HTTP status code of this response.
  int statusCode;

  /// The default constructor.
  ///
  /// There exist convenience constructors for common response status codes
  /// and you should prefer to use those.
  Response(int statusCode, Map<String, String> headers, dynamic body) {
    this.body = body;
    this.headers = headers;
    this.statusCode = statusCode;

    if (this.headers == null) {
      this.headers = {};
    }
  }

  Response.ok(dynamic body, {Map<String, String> headers})
      : this(HttpStatus.OK, headers, body);
  Response.created(String location,
      {dynamic body, Map<String, String> headers}) {
    this.headers = headers;
    this.body = body;
    this.statusCode = HttpStatus.CREATED;

    if (this.headers == null) {
      this.headers = {HttpHeaders.LOCATION: location};
    } else {
      this.headers[HttpHeaders.LOCATION] = location;
    }
  }
  Response.accepted({Map<String, String> headers})
      : this(HttpStatus.ACCEPTED, headers, null);

  Response.badRequest({Map<String, String> headers, dynamic body})
      : this(HttpStatus.BAD_REQUEST, headers, body);
  Response.unauthorized({Map<String, String> headers, dynamic body})
      : this(HttpStatus.UNAUTHORIZED, headers, body);
  Response.forbidden({Map<String, String> headers, dynamic body})
      : this(HttpStatus.FORBIDDEN, headers, body);
  Response.notFound({Map<String, String> headers, dynamic body})
      : this(HttpStatus.NOT_FOUND, headers, body);
  Response.conflict({Map<String, String> headers, dynamic body})
      : this(HttpStatus.CONFLICT, headers, body);
  Response.gone({Map<String, String> headers, dynamic body})
      : this(HttpStatus.GONE, headers, body);

  Response.serverError({Map<String, String> headers, dynamic body})
      : this(HttpStatus.INTERNAL_SERVER_ERROR, headers, body);

  String toString() {
    return "$statusCode $headers";
  }
}
