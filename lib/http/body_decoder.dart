part of aqueduct;

/// A decoding method for decoding a stream of bytes into a String based.
///
/// Typically, this represents the function [Utf8Codec.decodeStream].
typedef Future<String> HTTPBodyStreamDecoder(Stream<List<int>> s);

class HTTPBodyDecoder {
  /// The set of available decoders for HTTP request data.
  ///
  /// The HTTP header for Content-Type is broken into two pieces, primary type (e.g., 'application') and subtype (e.g., 'json').
  /// The primary type is the first key in [_decoders], and then the subtype is used to return the specific encoding
  /// function from this map. Decoders take a [HttpRequest] and return the decoded value of the request body based on the Content-Type pair.
  /// The following decoders are supported by default (you may add extra decoders using [addDecoder], do not manipulate [_decoders] directly.)
  ///
  ///       application/json
  ///       application/x-www-form-urlencoded
  ///       text/*
  ///
  static Map<String, Map<String, Function>> _decoders = {
    "application" : {
      "json" : _jsonDecoder,
      "x-www-form-urlencoded" : _wwwFormURLEncodedDecoder
    },
    "text" : {
      "*" : _textDecoder
    }
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
  static void addDecoder(ContentType type, Future<dynamic> decoder(HttpRequest req)) {
    var innerMap = _decoders[type.primaryType];
    if (innerMap == null) {
      innerMap = {};
      _decoders[type.primaryType] = innerMap;
    }

    innerMap[type.subType] = decoder;
  }

  static Future<dynamic> _jsonDecoder(HttpRequest req) async {
    var bodyAsString = await streamDecoderForCharset(req.headers.contentType.charset)(req);
    return JSON.decode(bodyAsString);
  }

  static Future<dynamic> _wwwFormURLEncodedDecoder(HttpRequest req) async {
    var bodyAsString = await streamDecoderForCharset(req.headers.contentType.charset, defaultEncoding: ASCII)(req);
    return new Uri(query: bodyAsString).queryParametersAll;
  }

  static Future<dynamic> _textDecoder(HttpRequest req) async {
    return streamDecoderForCharset(req.headers.contentType.charset, defaultEncoding: ASCII)(req);
  }

  static Future<dynamic> _binaryDecoder(HttpRequest req) async {
    BytesBuilder aggregatedBytes = await req.fold(new BytesBuilder(), (BytesBuilder builder, data) => builder..add(data));

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

    throw new HTTPBodyDecoderException("No decoder for ${request.headers.contentType}");
  }

  /// Returns a stream decoder for a character set.
  ///
  /// By default, this method will return the function [Utf8Codec.decodeStream]. This is a convenience
  /// method for decoding bytes in the specified charset.
  static HTTPBodyStreamDecoder streamDecoderForCharset(String charset, {Encoding defaultEncoding: UTF8}) {
    return (Encoding.getByName(charset) ?? defaultEncoding).decodeStream;
  }
}

/// Thrown when [HTTPBodyDecoder] encounters an exception.
class HTTPBodyDecoderException implements Exception {
  HTTPBodyDecoderException(this.message);

  String message;
}