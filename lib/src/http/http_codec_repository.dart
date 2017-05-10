import 'dart:convert';
import 'dart:io';
import 'http.dart';

class HTTPCodecRepository {
  static HTTPCodecRepository get defaultInstance => _defaultInstance;
  static HTTPCodecRepository _defaultInstance = new HTTPCodecRepository();

  HTTPCodecRepository() {
    add(new ContentType("application", "json"), const JsonCodec(), allowCompression: true);
    setAllowsCompression(new ContentType("text", "*"), true);
  }

  Map<String, Codec> _primaryTypeCodecs = {};
  Map<String, Map<String, Codec>> _subtypeCodecs = {};
  Map<String, bool> _primaryTypeCompressionMap = {};
  Map<String, Map<String, bool>> _subtypeCompressionMap = {};

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

  void setAllowsCompression(ContentType contentType, bool allowed) {
    if (contentType.subType == "*") {
      _primaryTypeCompressionMap[contentType.primaryType] = allowed;
    } else {
      var innerCompress = _subtypeCompressionMap[contentType.primaryType] ?? {};
      innerCompress[contentType.subType] = allowed;
      _subtypeCompressionMap[contentType.primaryType] = innerCompress;
    }
  }

  bool isContentTypeCompressable(ContentType contentType) {
    var subtypeCompress = _subtypeCompressionMap[contentType.primaryType];
    if (subtypeCompress != null) {
      if (subtypeCompress.containsKey(contentType.subType)) {
        return subtypeCompress[contentType.subType];
      }
    }

    return _primaryTypeCompressionMap[contentType.primaryType] ?? false;
  }

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

class HTTPCodecException implements Exception {
  HTTPCodecException(this.message);

  String message;

  String toString() => "HTTPCodecException: $message";
}
