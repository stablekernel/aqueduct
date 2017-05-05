import 'dart:convert';
import 'dart:io';
import 'http.dart';

class HTTPCodecRepository {
  static Map<String, Codec> _primaryTypeCodecs = {

  };
  static Map<String, Map<String, Codec>> _subtypeCodecs = {
    "application" : {
      "json": new JsonCodec()
    }
  };
  static Map<String, bool> _primaryTypeCompressionMap = {
    "text": true
  };
  static Map<String, Map<String, bool>> _subtypeCompressionMap = {
    "application" : {
      "json" : true
    }
  };

  static bool shouldGZipContentType(ContentType contentType) {
    var subtypeCompress = _subtypeCompressionMap[contentType.primaryType];
    if (subtypeCompress != null) {
      if (subtypeCompress.containsKey(contentType.subType)) {
        return subtypeCompress[contentType.subType];
      }
    }

    var primaryTypeCompress = _primaryTypeCompressionMap[contentType.primaryType];
    if (primaryTypeCompress) {
      return true;
    }

    return false;
  }

  static void add(ContentType contentType, Codec codec, {bool allowCompression: true}) {

  }

  static void allowCompressionFor(ContentType contentType) {

  }

  Codec codecForContentType(ContentType contentType, {bool withCompression: true}) {
    Codec contentCodec;
    Codec charsetCodec;
    Codec gzipCodec;

    var subtypes = _subtypeCodecs[contentType.primaryType];
    if (subtypes != null) {
      contentCodec = subtypes[contentType.subType];
    }

    if (contentCodec == null) {
      contentCodec = _primaryTypeCodecs[contentType.primaryType];
    }

    if ((contentType?.charset?.length ?? 0) > 0) {
      charsetCodec = _codecForCharset(contentType.charset);
    }

    if (withCompression && shouldGZipContentType(contentType)) {
      gzipCodec = GZIP;
    }

    if (contentCodec != null) {
      if (charsetCodec != null) {
        if (gzipCodec != null) {
          return contentCodec.fuse(charsetCodec).fuse(gzipCodec);
        }

        return contentCodec.fuse(charsetCodec);
      }
      return contentCodec;
    }

    if (charsetCodec != null) {
      if (gzipCodec != null) {
        return charsetCodec.fuse(gzipCodec);
      }

      return charsetCodec;
    }

    if (gzipCodec != null) {
      return gzipCodec;
    }

    return null;
  }

  Codec _codecForCharset(String charset) {
    var encoding = Encoding.getByName(charset);
    if (encoding == null) {
      throw new HTTPCodecRepositoryException("Invalid charset '$charset'");
    }

    return encoding;
  }
}

class HTTPCodecRepositoryException implements Exception {
  HTTPCodecRepositoryException(this.message);

  String message;

  String toString() => "HTTPCodecRepositoryException: $message";
}