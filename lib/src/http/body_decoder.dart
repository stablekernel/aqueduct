import 'dart:async';
import 'dart:io';
import 'dart:convert';

/// A decoding method for decoding a stream of bytes from an HTTP request body into a String.
///
/// This function is used as part of the [HTTPBodyDecoder] process. Typically, this represents the function [Utf8Codec.decodeStream].
typedef Future<String> HTTPBodyStreamDecoder(Stream<List<int>> s);

/// Instances of this class decode HTTP request bodies according to their content type.
///
/// Default decoders are available for 'application/json', 'application/x-www-form-urlencoded' and 'text/*'.
class HTTPBodyDecoder {
  static Map<String, Map<String, Function>> _decoders = {
    "application": {
      "json": _jsonDecoder,
      "x-www-form-urlencoded": _wwwFormURLEncodedDecoder
    },
    "text": {"*": _textDecoder}
  };

  /// Adds a decoder for HTTP Request Bodies.
  ///
  /// Adds a [decoder] function for [type] when reading [HttpRequest]s. Decoders are used by [Request]s to decode their body
  /// into the format indicated by the request's Content-Type, e.g. application/json. Decoding are most often initiated by invoking [Request.decodeBody], but can also be used more directly
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

  static Future<dynamic> _jsonDecoder(HttpRequest req) async {
    var bodyAsString =
        await streamDecoderForCharset(req.headers.contentType.charset)(req);
    return JSON.decode(bodyAsString);
  }

  static Future<dynamic> _wwwFormURLEncodedDecoder(HttpRequest req) async {
    var bodyAsString = await streamDecoderForCharset(
        req.headers.contentType.charset,
        defaultEncoding: ASCII)(req);
    return new Uri(query: bodyAsString).queryParametersAll;
  }

  static Future<dynamic> _textDecoder(HttpRequest req) async {
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
  /// for a matching decoding function in [_decoders]. If no such decoder is found, the body is returned as a [List] of bytes, where each byte is an [int].
  static Future<dynamic> decode(HttpRequest request) async {
    if (request.headers.contentType == null) {
      return _binaryDecoder(request);
    }

    var primaryType = request.headers.contentType.primaryType;
    var subType = request.headers.contentType.subType;

    var outerMap = _decoders[primaryType];
    if (outerMap == null) {
      return _binaryDecoder(request);
    }

    var decoder = outerMap[subType];
    if (decoder != null) {
      return decoder(request);
    }

    decoder = outerMap["*"];
    if (decoder != null) {
      return decoder(request);
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

/// Thrown when [HTTPBodyDecoder] encounters an exception.
class HTTPBodyDecoderException implements Exception {
  HTTPBodyDecoderException(this.message);

  final String message;
}
