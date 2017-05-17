import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'http.dart';

/// Serves files from a directory on the filesystem.
///
/// An instance of this type serves files by appending all or part of an HTTP request path to its [servingDirectory] and streaming the bytes
/// of that file as a response.
///
/// Instances of this type may be [pipe]d from a route that contains the match-all route pattern (`*`). For example, consider the following:
///
///       router
///        .route("/site/*")
///        .pipe(new HTTPFileController("build/web"));
///
/// In the above, `GET /site/index.html` would respond with the contents of the file `build/web/index.html`, relative to the project directory.
///
/// The content type of the response is determined by the file extension of the served file. There are many built-in extension-to-content-type mappings and you may
/// add more with [setContentTypeForExtension]. Unknown file extension will result in `application/octet-stream` content-type responses.
///
/// These mappings should be added in an application's [RequestSink] constructor.
///
/// Note that this controller will always compress files with `gzip` if the request has the appropriate header.
///
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

  /// Returns a [ContentType] for a file extension.
  ///
  /// Returns the associated content type for [extension], if one exists. Extension may have leading '.',
  /// e.g. both '.jpg' and 'jpg' are valid inputs to this method.
  ///
  /// Returns null if there is no entry for [extension]. Entries can be added with [setContentTypeForExtension].
  static ContentType contentTypeForExtension(String extension) {
    if (extension.startsWith(".")) {
      extension = extension.substring(1);
    }
    return _extensionMap[extension];
  }

  /// Sets the associated content type for a file extension.
  ///
  /// When a file with [extension] file extension is served by any instance of this type,
  /// the [contentType] will be sent as the response's Content-Type header.
  static void setContentTypeForExtension(
      String extension, ContentType contentType) {
    _extensionMap[extension] = contentType;
  }

  /// Serves files from [pathOfDirectoryToServe].
  ///
  /// See [HTTPFileController] for usage.
  ///
  /// [policy] is currently unimplemented.
  HTTPFileController(String pathOfDirectoryToServe, {HTTPCachePolicy policy})
      : servingDirectory = new Uri.directory(pathOfDirectoryToServe),
        cachePolicy = policy ?? new HTTPCachePolicy();

  /// Directory that files are served from.
  final Uri servingDirectory;

  /// HTTP Cache headers to apply to the responses from this instance.
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
      ..contentType = contentTypeForExtension(path.extension(file.path)
          ?? new ContentType("application", "octet-stream"));
  }
}