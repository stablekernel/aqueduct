import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'http.dart';

/// A decoding method for decoding a stream of bytes from an HTTP request body into a String.
///
/// This function is used as part of the [HTTPBody] process. Typically, this represents the function [Utf8Codec.decodeStream].
typedef Future<String> HTTPBodyStreamDecoder(Stream<List<int>> s);

/// Instances of this class decode HTTP request bodies according to their content type.
///
/// Every instance of [Request] has a [Request.body] property of this type. [HTTPController]s automatically decode
/// [Request.body] prior to invoking a responder method. Other [RequestController]s should use [decodedData]
/// or one of the typed methods ([asList], [asMap], [decodeAsMap], [decodeAsList]) to decode HTTP body data.
///
/// Default decoders are available for 'application/json', 'application/x-www-form-urlencoded' and 'text/*' content types.
class HTTPBody {
  static Map<String, Map<String, Function>> _decoders = {
    "application": {
      "json": _jsonDecoder,
      "x-www-form-urlencoded": _wwwFormURLEncodedDecoder
    },
    "text": {"*": _textDecoder}
  };

  /// Creates a new instance of this type.
  ///
  /// Instances of this type decode [request]'s body based on its content-type.
  ///
  /// See [addDecoder] for more information about how data is decoded.
  ///
  /// Decoded data is cached the after it is decoded.
  HTTPBody(HttpRequest request) : this._request = request;

  HttpRequest _request;
  dynamic _decodedData;

  /// Whether or not the data has been decoded yet.
  ///
  /// True when data has already been decoded.
  ///
  /// If this body has no content, this value is true.
  bool get hasBeenDecoded => _decodedData != null || !hasContent;

  /// Whether or not this body is empty or not.
  ///
  /// If content-length header is greater than 0.
  bool get hasContent {
    // todo: transfer-encoding
    return _request.headers.contentLength > 0;
  }

  /// Returns decoded data, decoding it if not already decoded.
  ///
  /// First access to this method will initiate decoding of the body,
  /// according to content-type of the request this instance was initialized with.
  /// Subsequent access will return cached decoded data.
  /// If the body is empty, this method will return null.
  ///
  /// See also [decodeAsMap], [decodeAsList] and [asMap] and [asList].
  Future<dynamic> get decodedData async {
    if (!hasBeenDecoded) {
      _decodedData ??= await HTTPBody.decode(_request);
    }

    return _decodedData;
  }

  /// Returns decoded data as [Map], decoding it if not already decoded.
  ///
  /// First access to this method will initiate decoding of the body,
  /// according to content-type of the request this instance was initialized with.
  /// Subsequent access will return cached decoded data.
  /// If the body is empty, this method will return null.
  ///
  /// If the body data was not decoded into a [Map] representation, an [HTTPBodyDecoderException] is thrown.
  /// Note that this method does not ensure that all map keys are [String].
  ///
  /// For a non-[Future] variant, see [asMap].
  Future<Map<String, dynamic>> decodeAsMap() async {
    var d = await decodedData;
    if (d == null) {
      return null;
    }
    if (d is! Map<String, dynamic>) {
      throw new HTTPBodyDecoderException("decodeAsMap() invoked on non-Map<String, dynamic> data.");
    }
    return d;
  }

  /// Returns decoded data as [List], decoding it if not already decoded.
  ///
  /// First access to this method will initiate decoding of the body,
  /// according to content-type of the request this instance was initialized with.
  /// Subsequent access will return cached decoded data.
  /// If the body is empty, this method will return null.
  ///
  /// If the body data was not decoded into a [List] representation, an [HTTPBodyDecoderException] is thrown.
  /// Note that this method does not ensure that all values are [Map].
  ///
  /// For a non-[Future] variant, see [asList].
  Future<List<Map<String, dynamic>>> decodeAsList() async {
    var d = await decodedData;
    if (d == null) {
      return null;
    }

    if (d is! List<Map<String, dynamic>>) {
      throw new HTTPBodyDecoderException("decodeAsList() invoked on non-List<Map<String, dynamic>> data.");
    }
    return d;

  }

  /// Returns decoded data as [Map] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsMap], but the result is not wrapped in [Future].
  Map<String, dynamic> asMap() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asMap() invoked, but has not been decoded yet.");
    }
    return _decodedData as Map<String, dynamic>;
  }

  /// Returns decoded data as [List] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodeAsList], but the result is not wrapped in [Future].
  List<dynamic> asList() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asList() invoked, but has not been decoded yet.");
    }

    return _decodedData as List<dynamic>;
  }

  /// Returns decoded data as [dynamic] if decoding has already occurred.
  ///
  /// If decoding has not yet occurred, this method throws an [HTTPBodyDecoderException].
  ///
  /// If decoding as occurred, behavior is the same as [decodedData], but the result is not wrapped in [Future].
  dynamic asDynamic() {
    if (!hasBeenDecoded) {
      throw new HTTPBodyDecoderException("asDynamic() invoked, but has not been decoded yet.");
    }

    return _decodedData;
  }

  /// Adds a decoder for HTTP Request Bodies, available application-wide.
  ///
  /// Adds a [decoder] function for [type] when reading [HttpRequest]s. Add decoders in a [RequestSink]'s constructor.
  /// Decoders are used by [Request]s to decode their body
  /// into the format indicated by the request's Content-Type, e.g. application/json. Decoding is most often initiated by [Request] instances, but can also be used more directly
  /// via [decode]. By default, there are decoders for the following content types:
  ///
  ///       application/json
  ///       application/x-www-form-urlencoded
  ///       text/*
  ///
  /// This method will replace an existing decoder if one exists. A [decoder] must return the decoded data as a [Future]. It takes a single [HttpRequest] as an argument. For example, the JSON encoder
  /// is implemented similar to the following:
  ///
  ///       Future<dynamic> jsonDecoder(HttpRequest req) async {
  ///         return JSON.decode(await UTF8.decodeStream(req));
  ///       }
  static void addDecoder(
      ContentType type, Future<dynamic> decoder(HttpRequest req)) {
    var innerMap = _decoders[type.primaryType];
    if (innerMap == null) {
      innerMap = {};
      _decoders[type.primaryType] = innerMap;
    }

    innerMap[type.subType] = decoder;
  }

  static Future<dynamic> _jsonDecoder(HttpRequest req) {
    return streamDecoderForCharset(req.headers.contentType.charset)(req)
        .then((str) => JSON.decode(str));
  }

  static Future<dynamic> _wwwFormURLEncodedDecoder(HttpRequest req) {
    return streamDecoderForCharset(req.headers.contentType.charset,
            defaultEncoding: ASCII)(req)
        .then(
            (bodyAsString) => new Uri(query: bodyAsString).queryParametersAll);
  }

  static Future<dynamic> _textDecoder(HttpRequest req) {
    return streamDecoderForCharset(req.headers.contentType.charset,
        defaultEncoding: ASCII)(req);
  }

  static Future<dynamic> _binaryDecoder(HttpRequest req) async {
    BytesBuilder aggregatedBytes = await req.fold(
        new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));

    return aggregatedBytes.takeBytes();
  }

  /// Decodes an [HttpRequest]'s body based on its Content-Type.
  ///
  /// This method will return the decoded object as a [Future]. The [HttpRequest]'s Content-Type is evaluated
  /// for a matching decoding function from [addDecoder]. If no such decoder is found, the body is returned as a [List] of bytes, where each byte is an [int].
  ///
  /// It is preferable to use [Request.body]'s [decodedData] method instead of this method directly.
  static Future<dynamic> decode(HttpRequest request) async {
    try {
      if (request.headers.contentType == null) {
        return await _binaryDecoder(request);
      }

      var primaryType = request.headers.contentType.primaryType;
      var subType = request.headers.contentType.subType;

      var outerMap = _decoders[primaryType];
      if (outerMap == null) {
        return await _binaryDecoder(request);
      }

      var decoder = outerMap[subType];
      if (decoder != null) {
        return await decoder(request);
      }

      decoder = outerMap["*"];
      if (decoder != null) {
        return await decoder(request);
      }
    } catch (e) {
      throw new HTTPBodyDecoderException("Exception encountered during decoding. Content-Type: ${request.headers.contentType}", underlyingException: e);
    }

    throw new HTTPBodyDecoderException(
        "No decoder for ${request.headers.contentType}");
  }

  /// Returns a stream decoder for a character set.
  ///
  /// By default, this method will return the function [Utf8Codec.decodeStream]. This is a convenience
  /// method for decoding bytes in the specified charset.
  static HTTPBodyStreamDecoder streamDecoderForCharset(String charset,
      {Encoding defaultEncoding: UTF8}) {
    return (Encoding.getByName(charset) ?? defaultEncoding).decodeStream;
  }
}

/// Thrown when [HTTPBody] encounters an exception.
class HTTPBodyDecoderException implements HTTPResponseException {
  HTTPBodyDecoderException(this.message, {this.underlyingException})
      : statusCode = 400;

  final String message;
  final dynamic underlyingException;

  final int statusCode;

  /// A [Response] object derived from this exception.
  Response get response {
    return new Response(statusCode, null, {"error": message})
      ..contentType = ContentType.JSON;
  }

  String toString() {
    return "HTTPBodyDecoderException: $message ${underlyingException == null ? "" : underlyingException}";
  }
}
