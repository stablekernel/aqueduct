import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'http.dart';

class HTTPFileController extends RequestController {
  static Map<String, ContentType> _extensionMap = {
    /* Web content */
    "html": new ContentType("text", "html", charset: "utf-8"),
    "css": new ContentType("text", "css", charset: "utf-8"),
    "js": new ContentType("application", "javascript", charset: "utf-8"),
    "json": new ContentType("application", "json", charset: "utf-8"),

    /* Images */
    "jpg": new ContentType("image", "jpeg"),
    "jpeg": new ContentType("image", "jpeg"),
    "eps": new ContentType("application", "postscript"),
    "png": new ContentType("image", "png"),
    "gif": new ContentType("image", "gif"),
    "bmp": new ContentType("image", "bmp"),
    "tiff": new ContentType("image", "tiff"),
    "tif": new ContentType("image", "tiff"),
    "ico": new ContentType("image", "x-icon"),
    "svg": new ContentType("image", "svg+xml"),

    /* Documents */
    "rtf": new ContentType("application", "rtf"),
    "pdf": new ContentType("application", "pdf"),
    "csv": new ContentType("text", "plain", charset: "utf-8"),
    "md": new ContentType("text", "plain", charset: "utf-8"),

    /* Fonts */
    "ttf": new ContentType("font", "ttf"),
    "eot": new ContentType("application", "vnd.ms-fontobject"),
    "woff": new ContentType("font", "woff"),
    "otf": new ContentType("font", "otf"),
  };

  static ContentType contentTypeForExtension(String extension) {
    if (extension.startsWith(".")) {
      extension = extension.substring(1);
    }
    return _extensionMap[extension] ??
        new ContentType("application", "octet-stream");
  }

  static void setContentTypeForExtension(
      String extension, ContentType contentType) {
    _extensionMap[extension] = contentType;
  }

  HTTPFileController(String pathOfDirectoryToServe, {HTTPCachePolicy policy})
      : servingDirectory = new Uri.directory(pathOfDirectoryToServe),
        cachePolicy = policy ?? new HTTPCachePolicy();

  final Uri servingDirectory;
  final HTTPCachePolicy cachePolicy;

  @override
  Future<RequestOrResponse> processRequest(Request request) async {
    var relativePath = request.path.remainingPath;
    var fileUri = servingDirectory.resolve(relativePath);
    File file;
    if (FileSystemEntity.isDirectorySync(fileUri.toFilePath())) {
      file = new File.fromUri(fileUri.resolve("index.html"));
    } else {
      file = new File.fromUri(fileUri);
    }

    if (!(await file.exists())) {
      return new Response.notFound();
    }

    var lastModifiedDate = HttpDate.format(await file.lastModified());
    var byteStream = file.openRead();

    return new Response.ok(byteStream,
        headers: {HttpHeaders.LAST_MODIFIED: lastModifiedDate})
      ..encodeBody = false
      ..contentType = contentTypeForExtension(path.extension(file.path));
  }
}
