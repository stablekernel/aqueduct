import 'dart:convert';
import 'dart:io';
import 'http.dart';

/// Provides encoding and decoding services based on the [ContentType] of a [Request] or [Response].
///
/// The [defaultInstance] provides a lookup table of [ContentType] to [Codec]. By default,
/// 'application/json', 'application/x-www-form-urlencoded' and 'text/*' content types have codecs and can
/// transform a [Response.body] into a list of bytes that can be transferred as an HTTP response body.
///
/// Additional mappings are added via [add]. This method must be called per-isolate and it is recommended
/// to add mappings in an application's [RequestSink] subclass constructor.
class HTTPCodecRepository {
  /// The instance used by Aqueduct to encode and decode HTTP bodies.
  ///
  /// Custom codecs must be added to this instance. This value is guaranteed to be non-null.
  static HTTPCodecRepository get defaultInstance => _defaultInstance;
  static HTTPCodecRepository _defaultInstance = new HTTPCodecRepository._();

  HTTPCodecRepository._() {
    add(new ContentType("application", "json"), const JsonCodec(), allowCompression: true);
    add(new ContentType("application", "x-www-form-urlencoded"), const _FormCodec(), allowCompression: true);
    setAllowsCompression(new ContentType("text", "*"), true);
  }


  Map<String, Codec> _primaryTypeCodecs = {};
  Map<String, Map<String, Codec>> _subtypeCodecs = {};
  Map<String, bool> _primaryTypeCompressionMap = {};
  Map<String, Map<String, bool>> _subtypeCompressionMap = {};

  /// Adds a custom [codec] for [contentType].
  ///
  /// The body of a [Response] sent with [contentType] will be transformed by [codec].
  ///
  /// [codec] may produce a [List<int>] or [String]. If it produces a [String],
  /// [contentType]'s primary type must be `text`. Specifying a charset for [contentType] has no effect,
  /// as a [Response] indicates the charset it will use.
  ///
  /// [contentType]'s subtype may be `*`; this signifies that matching is only done on the primary content type.
  /// For example, if [contentType] is `text/*`, then all `text/` (`text/html`, `text/plain`, etc.) content types
  /// are converted by [codec].
  ///
  /// The most specific codec for a content type is chosen when converting an HTTP body. For example, if both `text/*`
  /// and `text/html` have been added through this method, a [Response] with content type `text/html` will select the codec
  /// associated with `text/html` and not `text/*`.
  ///
  /// [allowCompression] chooses whether or not response bodies are compressed with [GZIP] when using [contentType].
  /// Media types like images and audio files should avoid setting [allowCompression] because they are already compressed.
  ///
  /// A response with a content type not in this instance will be sent unchanged to the HTTP client (and therefore must be [List<int>]
  void add(ContentType contentType, Codec codec, {bool allowCompression: true}) {
    if (contentType.subType == "*") {
      _primaryTypeCodecs[contentType.primaryType] = codec;
      _primaryTypeCompressionMap[contentType.primaryType] = allowCompression;
    } else {
      var innerCodecs = _subtypeCodecs[contentType.primaryType] ?? {};
      innerCodecs[contentType.subType] = codec;
      _subtypeCodecs[contentType.primaryType] = innerCodecs;

      var innerCompress = _subtypeCompressionMap[contentType.primaryType] ?? {};
      innerCompress[contentType.subType] = allowCompression;
      _subtypeCompressionMap[contentType.primaryType] = innerCompress;
    }
  }

  /// Toggles whether HTTP bodies of [contentType] are compressed with GZIP.
  ///
  /// Use this method when wanting to compress a [Response.body], but there is no need for a [Codec] to transform
  /// the body object.
  void setAllowsCompression(ContentType contentType, bool allowed) {
    if (contentType.subType == "*") {
      _primaryTypeCompressionMap[contentType.primaryType] = allowed;
    } else {
      var innerCompress = _subtypeCompressionMap[contentType.primaryType] ?? {};
      innerCompress[contentType.subType] = allowed;
      _subtypeCompressionMap[contentType.primaryType] = innerCompress;
    }
  }

  /// Whether or not [contentType] has been configured to be compressed.
  ///
  /// See also [setAllowsCompression].
  bool isContentTypeCompressable(ContentType contentType) {
    var subtypeCompress = _subtypeCompressionMap[contentType.primaryType];
    if (subtypeCompress != null) {
      if (subtypeCompress.containsKey(contentType.subType)) {
        return subtypeCompress[contentType.subType];
      }
    }

    return _primaryTypeCompressionMap[contentType.primaryType] ?? false;
  }

  /// Returns a [Codec] for [contentType].
  ///
  /// See [add].
  Codec codecForContentType(ContentType contentType) {
    Codec contentCodec;
    Codec charsetCodec;

    var subtypes = _subtypeCodecs[contentType.primaryType];
    if (subtypes != null) {
      contentCodec = subtypes[contentType.subType];
    }

    if (contentCodec == null) {
      contentCodec = _primaryTypeCodecs[contentType.primaryType];
    }

    if ((contentType?.charset?.length ?? 0) > 0) {
      charsetCodec = _codecForCharset(contentType.charset);
    } else if (contentType.primaryType == "text" && contentCodec == null) {
      charsetCodec = LATIN1;
    }


    if (contentCodec != null) {
      if (charsetCodec != null) {
        return contentCodec.fuse(charsetCodec);
      }
      return contentCodec;
    }

    if (charsetCodec != null) {
      return charsetCodec;
    }

    return null;
  }

  Codec _codecForCharset(String charset) {
    var encoding = Encoding.getByName(charset);
    if (encoding == null) {
      throw new HTTPCodecException("Invalid charset '$charset'");
    }

    return encoding;
  }
}

/// Thrown when [HTTPCodecRepository] encounters an exception.
class HTTPCodecException implements Exception {
  HTTPCodecException(this.message);

  String message;

  String toString() => "HTTPCodecException: $message";
}

class _FormCodec extends Codec {
  const _FormCodec();

  Converter<Map<String, dynamic>, dynamic> get encoder =>
      throw new HTTPCodecException("Cannot encode application/x-www-form-urlencoded data. This content type is only available for decoding.");

  Converter<dynamic, Map<String, dynamic>> get decoder => const _FormDecoder();
}


class _FormDecoder extends Converter<dynamic, Map<String, dynamic>> {
  // This class may take input as either String or List<int>. If charset is not defined in request,
  // then data is List<int> (from HTTPCodecRepository) and will default to being UTF8 decoded first.
  // Otherwise, if String, the request body has been decoded according to charset already.

  const _FormDecoder();

  Map<String, dynamic> convert(dynamic data) {
    if (data is! String) {
      if (data is List<int>) {
        data = UTF8.decode(data);
      } else {
        throw new HTTPCodecException("Invalid data type '${data.runtimeType}' for '_FormDecoder', must be 'List<int>' or 'String'");
      }
    }
    var parsed = new Uri(query: data);

    return parsed.queryParametersAll;
  }

  _FormSink startChunkedConversion(Sink<Map<String, dynamic>> outSink) {
    return new _FormSink(outSink);
  }
}

class _FormSink extends ChunkedConversionSink<dynamic> {
  _FormSink(this._outSink);

  final decoder = const _FormDecoder();
  final Sink<Map<String, dynamic>> _outSink;
  final StringBuffer _buffer = new StringBuffer();

  void add(dynamic data) {
    if (data is! String) {
      if (data is List<int>) {
        data = UTF8.decode(data);
      } else {
        throw new HTTPCodecException("Invalid data type '${data.runtimeType}' for '_FormDecoder', must be 'List<int>' or 'String'");
      }
    }
    _buffer.write(data);
  }

  void close() {
    _outSink.add(decoder.convert(_buffer.toString()));
    _outSink.close();
  }
}