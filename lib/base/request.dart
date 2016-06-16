part of aqueduct;

/// Represents a single HTTP request.
///
/// Contains a standard library [HttpRequest], along with other values
/// to associate data with a request.
class Request implements RequestHandlerResult {

  /// The set of available encoders for HTTP response data.
  ///
  /// If this [Request]'s [Response] has an HTTP body, the body is encoded
  /// with a function from this map of encoders. The HTTP header for Content-Type
  /// is broken into two pieces, primary type (e.g., 'application') and subtype (e.g., 'json').
  /// The primary type is the first key in [Encoders], and then the subtype is used to return the specific encoding
  /// function from this map. Encoders take any argument and return the encoded version of it based on those two values.
  /// By default, if a [Response] has no Content-Type header, 'application/json' is used. There are only two
  /// encoders available by default, 'application/json' and 'text/plain'. You may add extra encoders to this map using
  /// [addEncoder]. Do not try and manipulate [Encoders] directlry.
  static Map<String, Map<String, Function>> Encoders = {
    "application" : {
      "json" : (v) => JSON.encode(v),
    },
    "text" : {
      "plain" : (Object v) => v.toString()
    }
  };

  /// Adds an encoder for a content type. See [Encoders].
  static void addEncoder(ContentType type, dynamic encoder(dynamic value)) {
    var topLevel = Encoders[type.primaryType];
    if (topLevel == null) {
      topLevel = {};
      Encoders[topLevel] = topLevel;
    }

    topLevel[type.subType] = encoder;
  }

  /// Creates an instance of [Request], no need to do so manually.
  Request(this.innerRequest);

  /// The internal [HttpRequest] of this [Request].
  ///
  /// The standard library generated HTTP request object. This contains
  /// all of the request information provided by the client.
  final HttpRequest innerRequest;

  /// The response object of this [Request].
  ///
  /// To respond to a request, this object must be written to. It is the same
  /// instance as the [innerRequest]'s response.
  HttpResponse get response => innerRequest.response;

  /// The path and any extracted variable parameters from the URI of this request.
  ///
  /// Typically set by a [Router] instance when the request has been piped through one,
  /// this property will contain a list of each path segment, a map of matched variables,
  /// and any remaining wildcard path.
  RequestPath path;

  /// Permission information associated with this request.
  ///
  /// When this request goes through an [Authenticator], this value will be set with
  /// permission information from the authenticator. Use this to determine client, resource owner
  /// or other properties of the authentication information in the request. This value will be
  /// null if no permission has been set.
  Permission permission;

  /// The request body object, as determined by how it was decoded.
  ///
  /// This value will be null until [decodeBodyWithDecoder] is executed or if there is no request body.
  /// Once decoded, this value will be an object that is determined by the decoder passed to [decodeBodyWithDecoder].
  /// For example, if the request body was a JSON object and the decoder handled JSON, this value would be a [Map]
  /// representing the JSON object.
  dynamic requestBodyObject;

  /// The timestamp for when this request was received.
  DateTime receivedDate = new DateTime.now().toUtc();

  /// The timestamp for when this request was responded to.
  ///
  /// Used for logging.
  DateTime respondDate = null;

  /// Access to logger directly from this instance.
  Logger get logger => new Logger("aqueduct");

  String get _sanitizedHeaders {
    StringBuffer buf = new StringBuffer("{");
    innerRequest.headers.forEach((k, v) {
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

  Future decodeBodyWithDecoder(Future decoder(HttpRequest req)) async {
    if (innerRequest.contentLength > 0) {
      requestBodyObject = await decoder(innerRequest);
    }
  }

  /// Sends a [Response] to the requester.
  ///
  /// Once this method has executed, the [Request] is no longer valid.
  void respond(Response respObj) {
    respondDate = new DateTime.now().toUtc();

    response.statusCode = respObj.statusCode;

    if (respObj.headers != null) {
      respObj.headers.forEach((k, v) {
        if (v is ContentType) {
          response.headers.add(HttpHeaders.CONTENT_TYPE, v.toString());
        } else {
          response.headers.add(k, v);
        }
      });
    }

    if (respObj.body != null) {
      _encodeBody(respObj);
    }

    response.close();
  }

  void _encodeBody(Response respObj) {
    var contentTypeValue = respObj.headers["Content-Type"];
    if (contentTypeValue == null) {
      contentTypeValue = ContentType.JSON;
      response.headers.contentType = ContentType.JSON;
    } else if (contentTypeValue is String) {
      contentTypeValue = ContentType.parse(contentTypeValue);
    }

    ContentType contentType = contentTypeValue;
    var topLevel = Encoders[contentType.primaryType];
    if (topLevel == null) {
      throw new RequestException("No encoder for $contentTypeValue, add with ResourceRequest.addEncoder().");
    }

    var encoder = topLevel[contentType.subType];
    if (encoder == null) {
      throw new RequestException("No encoder for $contentTypeValue, add with ResourceRequest.addEncoder().");
    }

    var encodedValue = encoder(respObj.body);
    response.write(encodedValue);
  }

  String toString() {
    return "${innerRequest.method} ${this.innerRequest.uri} (${this.receivedDate.millisecondsSinceEpoch})";
  }

  String toDebugString({bool includeElapsedTime: true, bool includeRequestIP: true, bool includeMethod: true, bool includeResource: true, bool includeStatusCode: true, bool includeContentSize: false, bool includeHeaders: false, bool includeBody: false}) {
    var builder = new StringBuffer();
    if (includeRequestIP) {
      builder.write("${innerRequest.connectionInfo.remoteAddress.address} ");
    }
    if (includeMethod) {
      builder.write("${innerRequest.method} ");
    }
    if (includeResource) {
      builder.write("${innerRequest.uri} ");
    }
    if (includeElapsedTime && respondDate != null) {
      builder.write("${respondDate.difference(receivedDate).inMilliseconds}ms ");
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
