part of aqueduct;

/// Represents a single HTTP request.
///
/// Contains a standard library [HttpRequest], along with other values
/// to associate data with a request.
class ResourceRequest implements RequestHandlerResult {
  static Map<String, Map<String, Function>> Encoders = {
    "application" : {
      "json" : (v) => JSON.encode(v),
    },
    "text" : {
      "plain" : (Object v) => v.toString()
    }
  };

  static void addEncoder(ContentType type, dynamic encoder(dynamic value)) {
    var topLevel = Encoders[type.primaryType];
    if (topLevel == null) {
      topLevel = {};
      Encoders[topLevel] = topLevel;
    }

    topLevel[type.subType] = encoder;
  }

  ResourceRequest(this.innerRequest) {}

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

  /// The request body object, as determined by how it was decoded.
  ///
  /// This value will be null until [decodeBodyWithDecoder] is executed or if there is no request body.
  /// Once decoded, this value will be an object that is determined by the decoder passed to [decodeBodyWithDecoder].
  /// For example, if the request body was a JSON object and the decoder handled JSON, this value would be a [Map]
  /// representing the JSON object.
  dynamic requestBodyObject;

  DateTime receivedDate = new DateTime.now().toUtc();
  DateTime respondDate = null;
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

  void respond(Response respObj) {
    respondDate = new DateTime.now().toUtc();

    response.statusCode = respObj.statusCode;

    if (respObj.headers != null) {
      respObj.headers.forEach((k, v) {
        response.headers.add(k, v);
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
      throw new ResourceRequestException("No encoder for $contentTypeValue, add with ResourceRequest.addEncoder().");
    }

    var encoder = topLevel[contentType.subType];
    if (encoder == null) {
      throw new ResourceRequestException("No encoder for $contentTypeValue, add with ResourceRequest.addEncoder().");
    }

    var encodedValue = encoder(respObj.body);
    if (contentType.charset == "utf-8" || contentType.charset == null) {
      encodedValue = UTF8.encode(encodedValue);
    } else if (contentType == "us-ascii") {
      encodedValue = ASCII.encode(encodedValue);
    } else {
      throw new ResourceRequestException("Unsupported charset ${contentType.charset}");
    }

    List<int> bytes = encodedValue;
    response.headers.contentLength = bytes.length;
    response.add(bytes);
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

class ResourceRequestException implements Exception {
  ResourceRequestException(this.message);
  String message;
}
