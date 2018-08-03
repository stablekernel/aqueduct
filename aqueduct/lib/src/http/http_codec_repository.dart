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
/// to add mappings in an application's [ApplicationChannel] subclass constructor.
class CodecRegistry {
  CodecRegistry._() {
    add(ContentType("application", "json", charset: "utf-8"), const JsonCodec(),
        allowCompression: true);
    add(ContentType("application", "x-www-form-urlencoded", charset: "utf-8"),
        const _FormCodec(),
        allowCompression: true);
    setAllowsCompression(ContentType("text", "*"), true);
    setAllowsCompression(ContentType("application", "javascript"), true);
    setAllowsCompression(ContentType("text", "event-stream"), false);
  }

  /// The instance used by Aqueduct to encode and decode HTTP bodies.
  ///
  /// Custom codecs must be added to this instance. This value is guaranteed to be non-null.
  static CodecRegistry get defaultInstance => _defaultInstance;
  static CodecRegistry _defaultInstance = CodecRegistry._();

  Map<String, Codec> _primaryTypeCodecs = {};
  Map<String, Map<String, Codec>> _fullySpecificedCodecs = {};
  Map<String, bool> _primaryTypeCompressionMap = {};
  Map<String, Map<String, bool>> _fullySpecifiedCompressionMap = {};
  Map<String, Map<String, String>> _defaultCharsetMap = {};

  /// Adds a custom [codec] for [contentType].
  ///
  /// The body of a [Response] sent with [contentType] will be transformed by [codec]. A [Request] with [contentType] Content-Type
  /// will be decode its [Request.body] with [codec].
  ///
  /// [codec] must produce a [List<int>] (or used chunked conversion to create a `Stream<List<int>>`).
  ///
  /// [contentType]'s subtype may be `*`; all Content-Type's with a matching [ContentType.primaryType] will be
  /// encoded or decoded by [codec], regardless of [ContentType.subType]. For example, if [contentType] is `text/*`, then all
  /// `text/` (`text/html`, `text/plain`, etc.) content types are converted by [codec].
  ///
  /// The most specific codec for a content type is chosen when converting an HTTP body. For example, if both `text/*`
  /// and `text/html` have been added through this method, a [Response] with content type `text/html` will select the codec
  /// associated with `text/html` and not `text/*`.
  ///
  /// [allowCompression] chooses whether or not response bodies are compressed with [gzip] when using [contentType].
  /// Media types like images and audio files should avoid setting [allowCompression] because they are already compressed.
  ///
  /// A response with a content type not in this instance will be sent unchanged to the HTTP client (and therefore must be [List<int>]
  ///
  /// The [ContentType.charset] is not evaluated when selecting the codec for a content type. However, a charset indicates the default
  /// used when a request's Content-Type header omits a charset. For example, in order to decode JSON data, the request body must first be decoded
  /// from a list of bytes into a [String]. If a request omits the charset, this first step is would not be applied and the JSON codec would attempt
  /// to decode a list of bytes instead of a [String] and would fail. Thus, `application/json` is added through the following:
  ///
  ///         CodecRegistry.defaultInstance.add(
  ///           ContentType("application", "json", charset: "utf-8"), const JsonCodec(), allowsCompression: true);
  ///
  /// In the event that a request is sent without a charset, the codec will automatically apply a UTF8 decode step because of this default.
  ///
  /// Only use default charsets when the codec must first be decoded into a [String].
  void add(ContentType contentType, Codec codec,
      {bool allowCompression = true}) {
    if (contentType.subType == "*") {
      _primaryTypeCodecs[contentType.primaryType] = codec;
      _primaryTypeCompressionMap[contentType.primaryType] = allowCompression;
    } else {
      var innerCodecs = _fullySpecificedCodecs[contentType.primaryType] ?? {};
      innerCodecs[contentType.subType] = codec;
      _fullySpecificedCodecs[contentType.primaryType] = innerCodecs;

      var innerCompress =
          _fullySpecifiedCompressionMap[contentType.primaryType] ?? {};
      innerCompress[contentType.subType] = allowCompression;
      _fullySpecifiedCompressionMap[contentType.primaryType] = innerCompress;
    }

    if (contentType.charset != null) {
      var innerCodecs = _defaultCharsetMap[contentType.primaryType] ?? {};
      innerCodecs[contentType.subType] = contentType.charset;
      _defaultCharsetMap[contentType.primaryType] = innerCodecs;
    }
  }

  /// Toggles whether HTTP bodies of [contentType] are compressed with GZIP.
  ///
  /// Use this method when wanting to compress a [Response.body], but there is no need for a [Codec] to transform
  /// the body object.
  // ignore: avoid_positional_boolean_parameters
  void setAllowsCompression(ContentType contentType, bool allowed) {
    if (contentType.subType == "*") {
      _primaryTypeCompressionMap[contentType.primaryType] = allowed;
    } else {
      var innerCompress =
          _fullySpecifiedCompressionMap[contentType.primaryType] ?? {};
      innerCompress[contentType.subType] = allowed;
      _fullySpecifiedCompressionMap[contentType.primaryType] = innerCompress;
    }
  }

  /// Whether or not [contentType] has been configured to be compressed.
  ///
  /// See also [setAllowsCompression].
  bool isContentTypeCompressable(ContentType contentType) {
    var subtypeCompress =
        _fullySpecifiedCompressionMap[contentType.primaryType];
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
  Codec<dynamic, List<int>> codecForContentType(ContentType contentType) {
    if (contentType == null) {
      return null;
    }

    Codec contentCodec;
    Codec<String, List<int>> charsetCodec;

    var subtypes = _fullySpecificedCodecs[contentType.primaryType];
    if (subtypes != null) {
      contentCodec = subtypes[contentType.subType];
    }

    contentCodec ??= _primaryTypeCodecs[contentType.primaryType];

    if ((contentType?.charset?.length ?? 0) > 0) {
      charsetCodec = _codecForCharset(contentType.charset);
    } else if (contentType.primaryType == "text" && contentCodec == null) {
      charsetCodec = latin1;
    } else {
      charsetCodec = _defaultCharsetCodecForType(contentType);
    }

    if (contentCodec != null) {
      if (charsetCodec != null) {
        return contentCodec.fuse(charsetCodec);
      }
      if (contentCodec is! Codec<dynamic, List<int>>) {
        throw StateError("Invalid codec selected. Does not emit 'List<int>'.");
      }
      return contentCodec as Codec<dynamic, List<int>>;
    }

    if (charsetCodec != null) {
      return charsetCodec;
    }

    return null;
  }

  Codec<String, List<int>> _codecForCharset(String charset) {
    var encoding = Encoding.getByName(charset);
    if (encoding == null) {
      throw Response(415, null, {"error": "invalid charset '$charset'"});
    }

    return encoding;
  }

  Codec<String, List<int>> _defaultCharsetCodecForType(ContentType type) {
    var inner = _defaultCharsetMap[type.primaryType];
    if (inner == null) {
      return null;
    }

    var encodingName = inner[type.subType] ?? inner["*"];
    if (encodingName == null) {
      return null;
    }

    return Encoding.getByName(encodingName);
  }
}

class _FormCodec extends Codec<Map<String, dynamic>, dynamic> {
  const _FormCodec();

  @override
  Converter<Map<String, dynamic>, String> get encoder => const _FormEncoder();

  @override
  Converter<String, Map<String, dynamic>> get decoder => const _FormDecoder();
}

class _FormEncoder extends Converter<Map<String, dynamic>, String> {
  const _FormEncoder();

  @override
  String convert(Map<String, dynamic> data) {
    return data.keys.map((k) => _encodePair(k, data[k])).join("&");
  }

  String _encodePair(String key, dynamic value) {
    final encode = (String v) => "$key=${Uri.encodeQueryComponent(v)}";
    if (value is List<String>) {
      return value.map(encode).join("&");
    } else if (value is String) {
      return encode(value);
    }

    throw ArgumentError(
        "Cannot encode value '$value' for key '$key'. Must be 'String' or 'List<String>'");
  }
}

class _FormDecoder extends Converter<String, Map<String, dynamic>> {
  // This class may take input as either String or List<int>. If charset is not defined in request,
  // then data is List<int> (from CodecRegistry) and will default to being UTF8 decoded first.
  // Otherwise, if String, the request body has been decoded according to charset already.

  const _FormDecoder();

  @override
  Map<String, dynamic> convert(String data) {
    return Uri(query: data).queryParametersAll;
  }

  @override
  _FormSink startChunkedConversion(Sink<Map<String, dynamic>> outSink) {
    return _FormSink(outSink);
  }
}

class _FormSink extends ChunkedConversionSink<String> {
  _FormSink(this._outSink);

  final _FormDecoder decoder = const _FormDecoder();
  final Sink<Map<String, dynamic>> _outSink;
  final StringBuffer _buffer = StringBuffer();

  @override
  void add(String data) {
    _buffer.write(data);
  }

  @override
  void close() {
    _outSink.add(decoder.convert(_buffer.toString()));
    _outSink.close();
  }
}
