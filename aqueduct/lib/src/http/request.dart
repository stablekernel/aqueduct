import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/auth.dart';
import 'http.dart';

typedef _ResponseModifier = void Function(Response resp);

/// A single HTTP request.
///
/// Instances of this class travel through a [Controller] chain to be responded to, sometimes acquiring new values
/// as they go through controllers. Each instance of this class has a standard library [HttpRequest]. You should not respond
/// directly to the [HttpRequest], as [Controller]s take that responsibility.
class Request implements RequestOrResponse {
  /// Creates an instance of [Request], no need to do so manually.
  Request(this.raw)
      : path = RequestPath(raw.uri.pathSegments),
        body = RequestBody(raw);

  /// The underlying [HttpRequest] of this instance.
  ///
  /// Use this property to access values from the HTTP request that aren't accessible through this instance.
  ///
  /// You should typically not manipulate this property's [HttpRequest.response]. By default, Aqueduct controls
  /// the response through its [Controller]s.
  ///
  /// If you wish to respond to a request manually - and prohibit Aqueduct from responding to the request - you must
  /// remove this instance from the request channel. To remove a request from the channel, return null from a [Controller]
  /// handler method instead of a [Response] or [Request]. For example:
  ///
  ///         router.route("/raw").linkFunction((req) async {
  ///           req.response.statusCode = 200;
  ///           await req.response.close(); // Respond manually to request
  ///           return null; // Take request out of channel; no subsequent controllers will see this request.
  ///         });
  final HttpRequest raw;

  /// HTTP method of this request.
  ///
  /// Always uppercase. e.g., GET, POST, PUT.
  String get method => raw.method.toUpperCase();

  /// The path of the request URI.
  ///
  /// Provides convenient access to the request URI path. Also provides path variables and wildcard path values
  /// after this instance is handled by a [Router].
  final RequestPath path;

  /// The request body object.
  ///
  /// This object contains the request body if one exists and behavior for decoding it according
  /// to this instance's content-type. See [RequestBody] for details on decoding the body into
  /// an object (or objects).
  ///
  /// This value is is always non-null. If there is no request body, [RequestBody.isEmpty] is true.
  final RequestBody body;

  /// Information about the client connection.
  ///
  /// Note: accessing this property incurs a significant performance penalty.
  HttpConnectionInfo get connectionInfo => raw.connectionInfo;

  /// The response object of this [Request].
  ///
  /// Do not write to this value manually. [Controller]s are responsible for
  /// using a [Response] instance to fill out this property.
  HttpResponse get response => raw.response;

  /// Authorization information associated with this request.
  ///
  /// When this request goes through an [Authorizer], this value will be set with
  /// permission information from the authenticator. Use this to determine client, resource owner
  /// or other properties of the authentication information in the request. This value will be
  /// null if no permission has been set.
  Authorization authorization;

  List<_ResponseModifier> _responseModifiers;

  /// The acceptable content types for a [Response] returned for this instance.
  ///
  /// This list is determined by parsing the `Accept` header (or the concatenation
  /// of multiple `Accept` headers). The list is ordered such the more desirable
  /// content-types appear earlier in the list. Desirability is determined by
  /// a q-value (if one exists) and the specificity of the content-type.
  ///
  /// See also [acceptsContentType].
  List<ContentType> get acceptableContentTypes {
    if (_cachedAcceptableTypes == null) {
      try {
        var contentTypes = raw.headers[HttpHeaders.acceptHeader]
                ?.expand((h) => h.split(",").map((s) => s.trim()))
                ?.where((h) => h.isNotEmpty)
                ?.map(ContentType.parse)
                ?.toList() ??
            [];

        contentTypes.sort((c1, c2) {
          num q1 = num.parse(c1.parameters["q"] ?? "1.0");
          num q2 = num.parse(c2.parameters["q"] ?? "1.0");

          var comparison = q1.compareTo(q2);
          if (comparison == 0) {
            if (c1.primaryType == "*" && c2.primaryType != "*") {
              return 1;
            } else if (c1.primaryType != "*" && c2.primaryType == "*") {
              return -1;
            }

            if (c1.subType == "*" && c2.subType != "*") {
              return 1;
            } else if (c1.subType != "*" && c2.subType == "*") {
              return -1;
            }
          }

          return -comparison;
        });

        _cachedAcceptableTypes = contentTypes;
      } catch (_) {
        throw Response.badRequest(
            body: {"error": "accept header is malformed"});
      }
    }
    return _cachedAcceptableTypes;
  }

  List<ContentType> _cachedAcceptableTypes;

  /// Whether a [Response] may contain a body of type [contentType].
  ///
  /// This method searches [acceptableContentTypes] for a match with [contentType]. If one exists,
  /// this method returns true. Otherwise, it returns false.
  ///
  /// Note that if no Accept header is present, this method always returns true.
  bool acceptsContentType(ContentType contentType) {
    if (acceptableContentTypes.isEmpty) {
      return true;
    }

    return acceptableContentTypes.any((acceptable) {
      if (acceptable.primaryType == "*") {
        return true;
      }

      if (acceptable.primaryType == contentType.primaryType) {
        if (acceptable.subType == "*") {
          return true;
        }

        if (acceptable.subType == contentType.subType) {
          return true;
        }
      }

      return false;
    });
  }

  /// Whether or not this request is a CORS request.
  ///
  /// This is true if there is an Origin header.
  bool get isCORSRequest => raw.headers.value("origin") != null;

  /// Whether or not this is a CORS preflight request.
  ///
  /// This is true if the request HTTP method is OPTIONS and the headers contains Access-Control-Request-Method.
  bool get isPreflightRequest {
    return isCORSRequest &&
        raw.method == "OPTIONS" &&
        raw.headers.value("access-control-request-method") != null;
  }

  /// Container for any data a [Controller] wants to attach to this request for the purpose of being used by a later [Controller].
  ///
  /// Use this property to attach data to a [Request] for use by later [Controller]s.
  Map<dynamic, dynamic> attachments = {};

  /// The timestamp for when this request was received.
  DateTime receivedDate = DateTime.now().toUtc();

  /// The timestamp for when this request was responded to.
  ///
  /// Used for logging.
  DateTime respondDate;

  /// Allows a [Controller] to modify the response eventually created for this request, without creating that response itself.
  ///
  /// Executes [modifier] prior to sending the HTTP response for this request. Modifiers are executed in the order they were added and may contain
  /// modifiers from other [Controller]s. Modifiers are executed prior to any data encoded or is written to the network socket.
  ///
  /// This is valuable for middleware that wants to include some information in the response, but some other controller later in the channel
  /// will create the response. [modifier] will run prior to
  ///
  /// Usage:
  ///
  ///         Future<RequestOrResponse> handle(Request request) async {
  ///           request.addResponseModifier((r) {
  ///             r.headers["x-rate-limit-remaining"] = 200;
  ///           });
  ///           return request;
  ///         }
  void addResponseModifier(void modifier(Response response)) {
    _responseModifiers ??= [];
    _responseModifiers.add(modifier);
  }

  String get _sanitizedHeaders {
    StringBuffer buf = StringBuffer("{");

    raw?.headers?.forEach((k, v) {
      buf.write("${_truncatedString(k)} : ${_truncatedString(v.join(","))}\\n");
    });
    buf.write("}");

    return buf.toString();
  }

  String _truncatedString(String originalString, {int charSize = 128}) {
    if (originalString.length <= charSize) {
      return originalString;
    }
    return "${originalString.substring(0, charSize)} ... (${originalString.length - charSize} truncated bytes)";
  }

  /// Sends a [Response] to this [Request]'s client.
  ///
  /// Do not invoke this method directly.
  ///
  /// [Controller]s invoke this method to respond to this request.
  ///
  /// Once this method has executed, the [Request] is no longer valid. All headers from [aqueductResponse] are
  /// added to the HTTP response. If [aqueductResponse] has a [Response.body], this request will attempt to encode the body data according to the
  /// Content-Type in the [aqueductResponse]'s [Response.headers].
  ///
  Future respond(Response aqueductResponse) {
    respondDate = DateTime.now().toUtc();

    final modifiers = _responseModifiers;
    _responseModifiers = null;
    modifiers?.forEach((modifier) {
      modifier(aqueductResponse);
    });

    _Reference<String> compressionType = _Reference(null);
    var body = aqueductResponse.body;
    if (body is! Stream) {
      // Note: this pre-encodes the body in memory, such that encoding fails this will throw and we can return a 500
      // because we have yet to write to the response.
      body = _responseBodyBytes(aqueductResponse, compressionType);
    }

    response.statusCode = aqueductResponse.statusCode;
    aqueductResponse.headers?.forEach((k, v) {
      response.headers.add(k, v);
    });

    if (aqueductResponse.cachePolicy != null) {
      response.headers.add(HttpHeaders.cacheControlHeader,
          aqueductResponse.cachePolicy.headerValue);
    }

    if (body == null) {
      response.headers.removeAll(HttpHeaders.contentTypeHeader);
      return response.close();
    }

    response.headers.add(
        HttpHeaders.contentTypeHeader, aqueductResponse.contentType.toString());

    if (body is List<int>) {
      if (compressionType.value != null) {
        response.headers
            .add(HttpHeaders.contentEncodingHeader, compressionType.value);
      }
      response.headers.add(HttpHeaders.contentLengthHeader, body.length);

      response.add(body);

      return response.close();
    } else if (body is Stream) {
      // Otherwise, body is stream
      final bodyStream = _responseBodyStream(aqueductResponse, compressionType);
      if (compressionType.value != null) {
        response.headers
            .add(HttpHeaders.contentEncodingHeader, compressionType.value);
      }
      response.headers.add(HttpHeaders.transferEncodingHeader, "chunked");
      response.bufferOutput = aqueductResponse.bufferOutput;

      return response.addStream(bodyStream).then((_) {
        return response.close();
      }).catchError((e, StackTrace st) {
        throw HTTPStreamingException(e, st);
      });
    }

    throw StateError("Invalid response body. Could not encode.");
  }

  List<int> _responseBodyBytes(
      Response resp, _Reference<String> compressionType) {
    if (resp.body == null) {
      return null;
    }

    Codec<dynamic, List<int>> codec;
    if (resp.encodeBody) {
      codec =
          CodecRegistry.defaultInstance.codecForContentType(resp.contentType);
    }

    // todo(joeconwaystk): Set minimum threshold on number of bytes needed to perform gzip, do not gzip otherwise.
    // There isn't a great way of doing this that I can think of except splitting out gzip from the fused codec,
    // have to measure the value of fusing vs the cost of gzipping smaller data.
    var canGzip = CodecRegistry.defaultInstance
            .isContentTypeCompressable(resp.contentType) &&
        _acceptsGzipResponseBody;

    if (codec == null) {
      if (resp.body is! List<int>) {
        throw StateError(
            "Invalid response body. Body of type '${resp.body.runtimeType}' cannot be encoded as content-type '${resp.contentType}'.");
      }

      final bytes = resp.body as List<int>;
      if (canGzip) {
        compressionType.value = "gzip";
        return gzip.encode(bytes);
      }
      return bytes;
    }

    if (canGzip) {
      compressionType.value = "gzip";
      codec = codec.fuse(gzip);
    }

    return codec.encode(resp.body);
  }

  Stream<List<int>> _responseBodyStream(
      Response resp, _Reference<String> compressionType) {
    Codec<dynamic, List<int>> codec;
    if (resp.encodeBody) {
      codec =
          CodecRegistry.defaultInstance.codecForContentType(resp.contentType);
    }

    var canGzip = CodecRegistry.defaultInstance
            .isContentTypeCompressable(resp.contentType) &&
        _acceptsGzipResponseBody;
    if (codec == null) {
      if (resp.body is! Stream<List<int>>) {
        throw StateError(
            "Invalid response body. Body of type '${resp.body.runtimeType}' cannot be encoded as content-type '${resp.contentType}'.");
      }

      final stream = resp.body as Stream<List<int>>;
      if (canGzip) {
        compressionType.value = "gzip";
        return gzip.encoder.bind(stream);
      }

      return stream;
    }

    if (canGzip) {
      compressionType.value = "gzip";
      codec = codec.fuse(gzip);
    }

    return codec.encoder.bind(resp.body as Stream);
  }

  bool get _acceptsGzipResponseBody {
    return raw.headers[HttpHeaders.acceptEncodingHeader]
            ?.any((v) => v.split(",").any((s) => s.trim() == "gzip")) ??
        false;
  }

  @override
  String toString() {
    return "${raw.method} ${raw.uri} (${receivedDate.millisecondsSinceEpoch})";
  }

  /// A string that represents more details about the request, typically used for logging.
  ///
  /// Note: Setting includeRequestIP to true creates a significant performance penalty.
  String toDebugString(
      {bool includeElapsedTime = true,
      bool includeRequestIP = false,
      bool includeMethod = true,
      bool includeResource = true,
      bool includeStatusCode = true,
      bool includeContentSize = false,
      bool includeHeaders = false}) {
    var builder = StringBuffer();
    if (includeRequestIP) {
      builder.write("${raw.connectionInfo?.remoteAddress?.address} ");
    }
    if (includeMethod) {
      builder.write("${raw.method} ");
    }
    if (includeResource) {
      builder.write("${raw.uri} ");
    }
    if (includeElapsedTime && respondDate != null) {
      builder
          .write("${respondDate.difference(receivedDate).inMilliseconds}ms ");
    }
    if (includeStatusCode) {
      builder.write("${raw.response.statusCode} ");
    }
    if (includeContentSize) {
      builder.write("${raw.response.contentLength} ");
    }
    if (includeHeaders) {
      builder.write("$_sanitizedHeaders ");
    }

    return builder.toString();
  }
}

class HTTPStreamingException implements Exception {
  HTTPStreamingException(this.underlyingException, this.trace);

  dynamic underlyingException;
  StackTrace trace;
}

class _Reference<T> {
  _Reference(this.value);

  T value;
}
