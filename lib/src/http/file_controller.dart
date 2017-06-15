import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'http.dart';

/// Serves files from a directory on the filesystem.
///
/// See the constructor for usage.
///
class HTTPFileController extends RequestController {
  static Map<String, ContentType> _defaultExtensionMap = {
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

  /// Creates an instance of this type that serves files from [pathOfDirectoryToServe].
  ///
  /// An instance of this type serves files by appending all or part of an HTTP request path to [pathOfDirectoryToServe] and streaming the bytes
  /// of that file as a response.
  ///
  /// Instances of this type are [pipe]d from a route that MUST contain the match-all route pattern (`*`). For example, consider the following:
  ///
  ///       router
  ///        .route("/site/*")
  ///        .pipe(new HTTPFileController("build/web"));
  ///
  /// In the above, `GET /site/index.html` would respond with the contents of the file `build/web/index.html`, relative to the project directory.
  ///
  /// If [pathOfDirectoryToServe] contains a leading slash, it is an absolute path. Otherwise, it is relative to the current working directory
  /// of the running application.
  ///
  /// If no file is found, the default behavior is to return a 404 Not Found. (If the [Request] accepts 'text/html', a simple 404 page is returned.) You may
  /// override this behavior by providing [onFileNotFound]. The first argument to [onFileNotFound  is the instance of this type that could not find the file and
  /// may be accessed to use any settings like cache policies or content type mappings. The second argument is the request.
  ///
  /// The content type of the response is determined by the file extension of the served file. There are many built-in extension-to-content-type mappings and you may
  /// add more with [setContentTypeForExtension]. Unknown file extension will result in `application/octet-stream` content-type responses.
  ///
  /// The contents of a file will be compressed with 'gzip' if the request allows for it and the content-type of the file can be compressed
  /// according to [HTTPCodecRepository].
  ///
  /// Note that the 'Last-Modified' header is always applied to a response served from this instance.
  HTTPFileController(String pathOfDirectoryToServe,
      {Future<Response> onFileNotFound(HTTPFileController controller, Request req)})
      : _servingDirectory = new Uri.directory(pathOfDirectoryToServe),
        _onFileNotFound = onFileNotFound;

  Map<String, ContentType> _extensionMap =  new Map.from(_defaultExtensionMap);
  List<_PolicyPair> _policyPairs = [];
  final Uri _servingDirectory;
  final Function _onFileNotFound;

  /// Returns a [ContentType] for a file extension.
  ///
  /// Returns the associated content type for [extension], if one exists. Extension may have leading '.',
  /// e.g. both '.jpg' and 'jpg' are valid inputs to this method.
  ///
  /// Returns null if there is no entry for [extension]. Entries can be added with [setContentTypeForExtension].
  ContentType contentTypeForExtension(String extension) {
    if (extension.startsWith(".")) {
      extension = extension.substring(1);
    }
    return _extensionMap[extension];
  }

  /// Sets the associated content type for a file extension.
  ///
  /// When a file with [extension] file extension is served by any instance of this type,
  /// the [contentType] will be sent as the response's Content-Type header.
  void setContentTypeForExtension(
      String extension, ContentType contentType) {
    _extensionMap[extension] = contentType;
  }

  /// Add a cache policy for file paths that return true for [shouldApplyToPath].
  ///
  /// When this instance serves a file, the headers determined by [policy]
  /// will be applied to files whose path returns true for [shouldApplyToPath].
  ///
  /// If a path would meet the criteria for multiple [shouldApplyToPath] functions added to this instance,
  /// the policy added earliest to this instance will be applied.
  ///
  /// For example, the following adds a set of cache policies that will apply 'Cache-Control: no-cache, no-store' to '.widget' files,
  /// and 'Cache-Control: public' for any other files:
  ///
  ///         fileController.addCachePolicy(const HTTPCachePolicy(preventCaching: true),
  ///           (p) => p.endsWith(".widget"));
  ///         fileController.addCachePolicy(const HTTPCachePolicy(),
  ///           (p) => true);
  ///
  /// Whereas the following incorrect example would apply 'Cache-Control: public' to '.widget' files because the first policy
  /// would always apply to it and the second policy would be ignored:
  ///
  ///         fileController.addCachePolicy(const HTTPCachePolicy(),
  ///           (p) => true);
  ///         fileController.addCachePolicy(const HTTPCachePolicy(preventCaching: true),
  ///           (p) => p.endsWith(".widget"));
  ///
  /// Note that the 'Last-Modified' header is always applied to a response served from this instance.
  ///
  void addCachePolicy(HTTPCachePolicy policy, bool shouldApplyToPath(String path)) {
    _policyPairs.add(new _PolicyPair(policy, shouldApplyToPath));
  }

  /// Returns the [HTTPCachePolicy] for [path].
  ///
  /// Evaluates each policy added by [addCachePolicy] against the [path] and
  /// returns it if exists.
  HTTPCachePolicy cachePolicyForPath(String path) {
    return _policyPairs.firstWhere((pair) => pair.shouldApplyToPath(path),
        orElse: () => null)
        ?.policy;
  }

  @override
  Future<RequestOrResponse> processRequest(Request request) async {
    if (request.innerRequest.method.toLowerCase() != "get") {
      return new Response(HttpStatus.METHOD_NOT_ALLOWED, null, null);
    }

    var relativePath = request.path.remainingPath;
    var fileUri = _servingDirectory.resolve(relativePath);
    File file;
    if (FileSystemEntity.isDirectorySync(fileUri.toFilePath())) {
      file = new File.fromUri(fileUri.resolve("index.html"));
    } else {
      file = new File.fromUri(fileUri);
    }

    if (!(await file.exists())) {
      if (_onFileNotFound != null) {
        return _onFileNotFound(this, request);
      }
      var response = new Response.notFound();
      if (request.acceptsContentType(ContentType.HTML)) {
        response
          ..body = "<html><h3>404 Not Found</h3></html>"
          ..contentType = ContentType.HTML;
      }
      return response;
    }

    var lastModifiedDate = await file.lastModified();
    var ifModifiedSince = request.innerRequest.headers.value(HttpHeaders.IF_MODIFIED_SINCE);
    if (ifModifiedSince != null) {
      var date = HttpDate.parse(ifModifiedSince);
      if (!lastModifiedDate.isAfter(date)) {
        return new Response.notModified(lastModifiedDate, _policyForFile(file));
      }
    }

    var lastModifiedDateStringValue = HttpDate.format(lastModifiedDate);
    var contentType = contentTypeForExtension(path.extension(file.path))
        ?? new ContentType("application", "octet-stream");
    var byteStream = file.openRead();

    return new Response.ok(byteStream,
        headers: {HttpHeaders.LAST_MODIFIED: lastModifiedDateStringValue})
      ..cachePolicy = _policyForFile(file)
      ..encodeBody = false
      ..contentType = contentType;
  }

  HTTPCachePolicy _policyForFile(File file) => cachePolicyForPath(file.path);
}

typedef bool _ShouldApplyToPath(String path);
class _PolicyPair {
  _PolicyPair(this.policy, this.shouldApplyToPath);

  final _ShouldApplyToPath shouldApplyToPath;
  final HTTPCachePolicy policy;
}
