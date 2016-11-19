part of aqueduct;

/// Represents the information in an HTTP response.
///
/// This object can be used to write an HTTP response and contains conveniences
/// for creating these objects.
class Response implements RequestControllerEvent {
  /// The default value of a [contentType].
  ///
  /// If no [contentType] is set for an instance, this is the value used. By default, this value is
  /// [ContentType.JSON].
  static ContentType defaultContentType = ContentType.JSON;

  /// Adds an HTTP Response Body encoder to list of available encoders for all [Request]s.
  ///
  /// When the [contentType] of an instance is set, an encoder function is applied to the data. This method
  /// adds an encoder function for [type].
  ///
  /// By default, 'application/json' and 'text/*' are available. A [Response] with "application/json" [contentType]
  /// will be encoded by invoking [JSON.decode] on the instance's [body]. The default encoder for [ContentType]s whose primary type is "text" will invoke [toString]
  /// on the instance's [body].
  ///
  /// [type] can have a '*' [ContentType.subType] that matches all subtypes for a primary type.
  ///
  /// An [encoder] must take one argument of any type, and return a value
  /// that will become the HTTP response body.
  ///
  /// The return value is written to the response with [IOSink.write] and so it must either be a [String] or its [toString]
  /// must produce the desired value.
  static void addEncoder(ContentType type, dynamic encoder(dynamic value)) {
    var topLevel = _encoders[type.primaryType];
    if (topLevel == null) {
      topLevel = {};
      _encoders[type.primaryType] = topLevel;
    }

    topLevel[type.subType] = encoder;
  }

  static Map<String, Map<String, Function>> _encoders = {
    "application": {
      "json": (v) => JSON.encode(v),
    },
    "text" : {
      "*" : (Object v) => v.toString()
    }
  };

  /// An object representing the body of the [Response], which will be encoded when used to [Request.respond].
  ///
  /// This is typically a map or list of maps that will be encoded to JSON. If the [body] was previously set with a [HTTPSerializable] object
  /// or a list of [HTTPSerializable] objects, this property will be the already serialized (but not encoded) body.
  dynamic get body => _body;

  /// Sets the unencoded response body.
  ///
  /// This may be any value that can be encoded into an HTTP response body. If this value is a [HTTPSerializable] or a [List] of [HTTPSerializable],
  /// each instance of [HTTPSerializable] will transformed via its [HTTPSerializable.asSerializable] method before being set.
  void set body(dynamic initialResponseBody) {
    var serializedBody = null;
    if (initialResponseBody is HTTPSerializable) {
      serializedBody = initialResponseBody.asSerializable();
    } else if (initialResponseBody is List) {
      serializedBody = initialResponseBody.map((value) {
        if (value is HTTPSerializable) {
          return value.asSerializable();
        } else {
          return value;
        }
      }).toList();
    }

    _body = serializedBody ?? initialResponseBody;
  }

  dynamic _body;

  /// Returns the encoded [body] according to [contentType].
  ///
  /// If there is no [body] present, this property is null. This property will use the encoders available through [addEncoder]. If
  /// no encoder is found, [toString] is called on the body.
  dynamic get encodedBody {
    if (_body == null) {
      return null;
    }

    var encoder = null;
    var topLevel = _encoders[contentType.primaryType];
    if (topLevel != null) {
      encoder = topLevel[contentType.subType] ?? topLevel["*"];
    }

    if (encoder == null) {
      throw new HTTPResponseException(500, "Could not encode body as ${contentType.toString()}.");
    }

    return encoder(_body);
  }

  /// Map of headers to send in this response.
  ///
  /// Where the key is the Header name and value is the Header value. Values may be any type and by default will have [toString] invoked
  /// on them. For [DateTime] values, the value will be converted into an HTTP date format. For [List] values, each value will be
  /// have [toString] invoked on it and the resulting outputs will be joined together with the "," character.
  ///
  /// Adding a Content-Type header through this property has no effect. Use [contentType] instead.
  Map<String, dynamic> headers;

  /// The HTTP status code of this response.
  int statusCode;

  /// The content type of the body of this response.
  ///
  /// Defaults to [defaultContentType]. This response's body will be encoded according to this value.
  /// The Content-Type header of the HTTP response will always be set according to this value.
  ContentType get contentType => _contentType ?? defaultContentType;
  void set contentType(ContentType t) {
    _contentType = t;
  }
  ContentType _contentType;

  /// Whether or nor this instance has explicitly has its [contentType] property.
  ///
  /// This value indicates whether or not [contentType] has been set, or is still using its default value.
  ///
  /// Some [RequestController]s might provide a value for this instance's Content-Type. For example,
  /// an [HTTPController] has a [HTTPController.responseContentType] that it applies
  bool get hasExplicitlySetContentType => _contentType != null;

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
  Response.ok(dynamic body, {Map<String, dynamic> headers})
      : this(HttpStatus.OK, headers, body);

  /// Represents a 201 response.
  ///
  /// The [location] is a URI that is added as the Location header.
  Response.created(String location,
      {dynamic body, Map<String, dynamic> headers}) {
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
  Response.accepted({Map<String, dynamic> headers})
      : this(HttpStatus.ACCEPTED, headers, null);

  /// Represents a 400 response.
  Response.badRequest({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.BAD_REQUEST, headers, body);

  /// Represents a 401 response.
  Response.unauthorized({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.UNAUTHORIZED, headers, body);

  /// Represents a 403 response.
  Response.forbidden({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.FORBIDDEN, headers, body);

  /// Represents a 404 response.
  Response.notFound({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.NOT_FOUND, headers, body);

  /// Represents a 409 response.
  Response.conflict({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.CONFLICT, headers, body);

  /// Represents a 410 response.
  Response.gone({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.GONE, headers, body);

  /// Represents a 500 response.
  Response.serverError({Map<String, dynamic> headers, dynamic body})
      : this(HttpStatus.INTERNAL_SERVER_ERROR, headers, body);

  String toString() {
    return "$statusCode $headers";
  }
}
