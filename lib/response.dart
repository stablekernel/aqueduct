part of monadart;

/// Represents the information in an HTTP response.
///
/// This object can be used to write an HTTP response and contains conveniences
/// for creating these objects.
class Response {

  /// An object representing the body of the [Response], which will be encoded later.
  ///
  /// This is typically a map that will be encoded to JSON.
  dynamic body;

  ///
  HttpHeaders headers;

  /// The HTTP status code of this response.
  int statusCode;

  /// The default constructor.
  ///
  /// There exist convenience constructors for common response status codes
  /// and you should prefer to use those.
  Response(int statusCode, HttpHeaders headers, dynamic body) {
    this.body = body;
    this.headers = headers;
    this.statusCode = statusCode;
  }

  Response.ok(dynamic body, {HttpHeaders headers}) : this(HttpStatus.OK, headers, body);
  Response.created(String location, {dynamic body, HttpHeaders headers}) {
    this.headers = headers;
    this.body = body;
    this.statusCode = HttpStatus.CREATED;

    this.headers.set(HttpHeaders.LOCATION, location);
  }
  Response.accepted({HttpHeaders headers}) : this(HttpStatus.ACCEPTED, headers, null);

  Response.badRequest({HttpHeaders headers, dynamic body}) : this(HttpStatus.BAD_REQUEST, headers, body);
  Response.unauthorized({HttpHeaders headers, dynamic body}) : this(HttpStatus.UNAUTHORIZED, headers, body);
  Response.forbidden({HttpHeaders headers, dynamic body}) : this(HttpStatus.FORBIDDEN, headers, body);
  Response.notFound({HttpHeaders headers, dynamic body}) : this(HttpStatus.NOT_FOUND, headers, body);
  Response.conflict({HttpHeaders headers, dynamic body}) : this(HttpStatus.CONFLICT, headers, body);
  Response.gone({HttpHeaders headers, dynamic body}) : this(HttpStatus.GONE, headers, body);

  Response.serverError({HttpHeaders headers, dynamic body}) : this(HttpStatus.INTERNAL_SERVER_ERROR, headers, body);

}