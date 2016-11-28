part of aqueduct;

/// A single HTTP request.
///
/// Instances of this class travel through a [RequestController] chain to be responded to, sometimes acquiring new values
/// as they go through controllers. Each instance of this class has a standard library [HttpRequest]. You should not respond
/// directly to the [HttpRequest], as [RequestController]s take that responsibility.
class Request implements RequestControllerEvent {
  /// Creates an instance of [Request], no need to do so manually.
  Request(this.innerRequest) {
    connectionInfo = innerRequest.connectionInfo;
  }

  /// The internal [HttpRequest] of this [Request].
  ///
  /// The standard library generated HTTP request object. This contains
  /// all of the request information provided by the client. Do not respond
  /// to this value directly.
  final HttpRequest innerRequest;

  /// Information about the client connection.
  HttpConnectionInfo connectionInfo;

  /// The response object of this [Request].
  ///
  /// Do not write to this value manually. [RequestController]s are responsible for
  /// using a [Response] instance to fill out this property.
  HttpResponse get response => innerRequest.response;

  /// The path and any extracted variable parameters from the URI of this request.
  ///
  /// Typically set by a [Router] instance when the request has been piped through one,
  /// this property will contain a list of each path segment, a map of matched variables,
  /// and any remaining wildcard path.
  HTTPRequestPath path;

  /// Authorization information associated with this request.
  ///
  /// When this request goes through an [Authorizer], this value will be set with
  /// permission information from the authenticator. Use this to determine client, resource owner
  /// or other properties of the authentication information in the request. This value will be
  /// null if no permission has been set.
  Authorization authorization;

  /// The request body object, as determined by how it was decoded.
  ///
  /// This value will be null until [decodeBody] is executed or if there is no request body.
  /// Once decoded, this value will be an object that is determined by the decoder passed to [decodeBody].
  /// For example, if the request body was a JSON object and the decoder handled JSON, this value would be a [Map]
  /// representing the JSON object.
  dynamic requestBodyObject;

  /// Whether or not this request is a CORS request.
  ///
  /// This is true if there is an Origin header.
  bool get isCORSRequest => innerRequest.headers.value("origin") != null;

  /// Whether or not this is a CORS preflight request.
  ///
  /// This is true if the request HTTP method is OPTIONS and the headers contains Access-Control-Request-Method.
  bool get isPreflightRequest {
    return isCORSRequest &&
        innerRequest.method == "OPTIONS" &&
        innerRequest.headers.value("access-control-request-method") != null;
  }

  /// Container for any data a [RequestController] wants to attach to this request for the purpose of being used by a later [RequestController].
  ///
  /// Use this property to attach data to a [Request] for use by later [RequestController]s.
  Map<dynamic, dynamic> attachments = {};

  /// The timestamp for when this request was received.
  DateTime receivedDate = new DateTime.now().toUtc();

  /// The timestamp for when this request was responded to.
  ///
  /// Used for logging.
  DateTime respondDate = null;

  /// Access to logger directly from this instance.
  Logger get logger => new Logger("aqueduct");

  /// Decodes the body of this request according to its Content-Type.
  ///
  /// This method initiates the decoding of this request's body according to its Content-Type, returning a [Future] that completes
  /// with the decoded object when decoding has finished. The decoded body is also available in [requestBodyObject] once decoding has completed.
  /// This method may be called multiple times; decoding will only occur once. If there is no request body, this method will return a [Future] that completes
  /// with the null value.
  ///
  /// [HTTPController]s invoke this method prior to invoking their responder method, so there is no need to call this method in a [HTTPController].
  Future decodeBody() async {
    if (innerRequest.contentLength > 0) {
      requestBodyObject ??= await HTTPBodyDecoder.decode(innerRequest);
    }

    return requestBodyObject;
  }

  String get _sanitizedHeaders {
    StringBuffer buf = new StringBuffer("{");

    innerRequest?.headers?.forEach((k, v) {
      buf.write("${_truncatedString(k)} : ${_truncatedString(v.join(","))}\\n");
    });
    buf.write("}");

    return buf.toString();
  }

  String get _sanitizedBody {
    if (requestBodyObject != null) {
      return _truncatedString("$requestBodyObject", charSize: 512);
    }

    return "-";
  }

  String _truncatedString(String originalString, {int charSize: 128}) {
    if (originalString.length <= charSize) {
      return originalString;
    }
    return originalString.substring(0, charSize);
  }

  /// Sends a [Response] to this [Request]'s client.
  ///
  /// [RequestController]s invoke this method to respond to this request.
  ///
  /// Once this method has executed, the [Request] is no longer valid. All headers from [responseObject] are
  /// added to the HTTP response. If [responseObject] has a [Response.body], this request will attempt to encode the body data according to the
  /// Content-Type in the [responseObject]'s [Response.headers].
  ///
  /// By default, 'application/json' and 'text/plain' are supported HTTP response body encoding types. If you wish to encode another
  /// format, see [Response.addEncoder].
  void respond(Response responseObject) {
    respondDate = new DateTime.now().toUtc();

    var encodedBody = responseObject.encodedBody;

    response.statusCode = responseObject.statusCode;

    if (responseObject.headers != null) {
      responseObject.headers.forEach((k, v) {
        response.headers.add(k, v);
      });
    }

    if (encodedBody != null) {
      response.headers
          .add(HttpHeaders.CONTENT_TYPE, responseObject.contentType.toString());
      response.write(encodedBody);
    }

    response.close();
  }

  String toString() {
    return "${innerRequest.method} ${this.innerRequest.uri} (${this.receivedDate.millisecondsSinceEpoch})";
  }

  /// A string that represents more details about the request, typically used for logging.
  String toDebugString(
      {bool includeElapsedTime: true,
      bool includeRequestIP: true,
      bool includeMethod: true,
      bool includeResource: true,
      bool includeStatusCode: true,
      bool includeContentSize: false,
      bool includeHeaders: false,
      bool includeBody: false}) {
    var builder = new StringBuffer();
    if (includeRequestIP) {
      builder.write("${innerRequest.connectionInfo?.remoteAddress?.address} ");
    }
    if (includeMethod) {
      builder.write("${innerRequest.method} ");
    }
    if (includeResource) {
      builder.write("${innerRequest.uri} ");
    }
    if (includeElapsedTime && respondDate != null) {
      builder
          .write("${respondDate.difference(receivedDate).inMilliseconds}ms ");
    }
    if (includeStatusCode) {
      builder.write("${innerRequest.response.statusCode} ");
    }
    if (includeContentSize) {
      builder.write("${innerRequest.response.contentLength} ");
    }
    if (includeHeaders) {
      builder.write("${_sanitizedHeaders} ");
    }
    if (includeBody) {
      builder.write("${_sanitizedBody} ");
    }

    return builder.toString();
  }
}

/// Thrown when a [Request] encounters an error.
class RequestException implements Exception {
  RequestException(this.message);
  String message;
}
