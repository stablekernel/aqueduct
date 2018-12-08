import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:path/path.dart' as path;
import 'http.dart';

typedef _OnFileNotFound = FutureOr<Response> Function(
    FileController controller, Request req);

/// Serves files from a directory on the filesystem.
///
/// See the constructor for usage.
class FileController extends Controller {
  /// Creates a controller that serves files from [pathOfDirectoryToServe].
  ///
  /// File controllers append the path of an HTTP request to [pathOfDirectoryToServe] and attempt to read the file at that location.
  ///
  /// If the file exists, its contents are sent in the HTTP Response body. If the file does not exist, a 404 Not Found error is returned by default.
  ///
  /// A route to this controller must contain the match-all segment (`*`). For example:
  ///
  ///       router
  ///        .route("/site/*")
  ///        .link(() => FileController("build/web"));
  ///
  /// In the above, `GET /site/index.html` would return the file `build/web/index.html`.
  ///
  /// If [pathOfDirectoryToServe] contains a leading slash, it is an absolute path. Otherwise, it is relative to the current working directory
  /// of the running application.
  ///
  /// If no file is found, the default behavior is to return a 404 Not Found. (If the [Request] accepts 'text/html', a simple 404 page is returned.) You may
  /// override this behavior by providing [onFileNotFound].
  ///
  /// The content type of the response is determined by the file extension of the served file. There are many built-in extension-to-content-type mappings and you may
  /// add more with [setContentTypeForExtension]. Unknown file extension will result in `application/octet-stream` content-type responses.
  ///
  /// The contents of a file will be compressed with 'gzip' if the request allows for it and the content-type of the file can be compressed
  /// according to [CodecRegistry].
  ///
  /// Note that the 'Last-Modified' header is always applied to a response served from this instance.
  FileController(String pathOfDirectoryToServe,
    {FutureOr<Response> onFileNotFound(
      FileController controller, Request req)})
    : _servingDirectory = Uri.directory(pathOfDirectoryToServe),
      _onFileNotFound = onFileNotFound;

  static Map<String, ContentType> _defaultExtensionMap = {
    /* Web content */
    "html": ContentType("text", "html", charset: "utf-8"),
    "css": ContentType("text", "css", charset: "utf-8"),
    "js": ContentType("application", "javascript", charset: "utf-8"),
    "json": ContentType("application", "json", charset: "utf-8"),

    /* Images */
    "jpg": ContentType("image", "jpeg"),
    "jpeg": ContentType("image", "jpeg"),
    "eps": ContentType("application", "postscript"),
    "png": ContentType("image", "png"),
    "gif": ContentType("image", "gif"),
    "bmp": ContentType("image", "bmp"),
    "tiff": ContentType("image", "tiff"),
    "tif": ContentType("image", "tiff"),
    "ico": ContentType("image", "x-icon"),
    "svg": ContentType("image", "svg+xml"),

    /* Documents */
    "rtf": ContentType("application", "rtf"),
    "pdf": ContentType("application", "pdf"),
    "csv": ContentType("text", "plain", charset: "utf-8"),
    "md": ContentType("text", "plain", charset: "utf-8"),

    /* Fonts */
    "ttf": ContentType("font", "ttf"),
    "eot": ContentType("application", "vnd.ms-fontobject"),
    "woff": ContentType("font", "woff"),
    "otf": ContentType("font", "otf"),
  };

  final Map<String, ContentType> _extensionMap = Map.from(_defaultExtensionMap);
  final List<_PolicyPair> _policyPairs = [];
  final Uri _servingDirectory;
  final _OnFileNotFound _onFileNotFound;

  /// Returns a [ContentType] for a file extension.
  ///
  /// Returns the associated content type for [extension], if one exists. Extension may have leading '.',
  /// e.g. both '.jpg' and 'jpg' are valid inputs to this method.
  ///
  /// Returns null if there is no entry for [extension]. Entries can be added with [setContentTypeForExtension].
  ContentType contentTypeForExtension(String extension) {
    if (extension.startsWith(".")) {
      return _extensionMap[extension.substring(1)];
    }
    return _extensionMap[extension];
  }

  /// Sets the associated content type for a file extension.
  ///
  /// When a file with [extension] file extension is served by any instance of this type,
  /// the [contentType] will be sent as the response's Content-Type header.
  void setContentTypeForExtension(String extension, ContentType contentType) {
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
  ///         fileController.addCachePolicy(const CachePolicy(preventCaching: true),
  ///           (p) => p.endsWith(".widget"));
  ///         fileController.addCachePolicy(const CachePolicy(),
  ///           (p) => true);
  ///
  /// Whereas the following incorrect example would apply 'Cache-Control: public' to '.widget' files because the first policy
  /// would always apply to it and the second policy would be ignored:
  ///
  ///         fileController.addCachePolicy(const CachePolicy(),
  ///           (p) => true);
  ///         fileController.addCachePolicy(const CachePolicy(preventCaching: true),
  ///           (p) => p.endsWith(".widget"));
  ///
  /// Note that the 'Last-Modified' header is always applied to a response served from this instance.
  ///
  void addCachePolicy(CachePolicy policy, bool shouldApplyToPath(String path)) {
    _policyPairs.add(_PolicyPair(policy, shouldApplyToPath));
  }

  /// Returns the [CachePolicy] for [path].
  ///
  /// Evaluates each policy added by [addCachePolicy] against the [path] and
  /// returns it if exists.
  CachePolicy cachePolicyForPath(String path) {
    return _policyPairs
        .firstWhere((pair) => pair.shouldApplyToPath(path), orElse: () => null)
        ?.policy;
  }

  @override
  Future<RequestOrResponse> handle(Request request) async {
    if (request.method != "GET") {
      return Response(HttpStatus.methodNotAllowed, null, null);
    }

    var relativePath = request.path.remainingPath;
    var fileUri = _servingDirectory.resolve(relativePath);
    File file;
    if (FileSystemEntity.isDirectorySync(fileUri.toFilePath())) {
      file = File.fromUri(fileUri.resolve("index.html"));
    } else {
      file = File.fromUri(fileUri);
    }

    if (!file.existsSync()) {
      if (_onFileNotFound != null) {
        return _onFileNotFound(this, request);
      }

      var response = Response.notFound();
      if (request.acceptsContentType(ContentType.html)) {
        response
          ..body = "<html><h3>404 Not Found</h3></html>"
          ..contentType = ContentType.html;
      }
      return response;
    }

    var lastModifiedDate = file.lastModifiedSync();
    var ifModifiedSince =
        request.raw.headers.value(HttpHeaders.ifModifiedSinceHeader);
    if (ifModifiedSince != null) {
      var date = HttpDate.parse(ifModifiedSince);
      if (!lastModifiedDate.isAfter(date)) {
        return Response.notModified(lastModifiedDate, _policyForFile(file));
      }
    }

    var lastModifiedDateStringValue = HttpDate.format(lastModifiedDate);
    var contentType = contentTypeForExtension(path.extension(file.path)) ??
        ContentType("application", "octet-stream");
    var byteStream = file.openRead();

    return Response.ok(byteStream,
        headers: {HttpHeaders.lastModifiedHeader: lastModifiedDateStringValue})
      ..cachePolicy = _policyForFile(file)
      ..encodeBody = false
      ..contentType = contentType;
  }

  @override
  Map<String, APIOperation> documentOperations(
      APIDocumentContext context, String route, APIPath path) {
    return {
      "get": APIOperation(
          "getFile",
          {
            "200": APIResponse("Successful file fetch.",
                content: {"*/*": APIMediaType(schema: APISchemaObject.file())}),
            "404": APIResponse("No file exists at path.")
          },
          description: "Content-Type is determined by the suffix of the file.",
          summary: "Returns the contents of a file on the server's filesystem.")
    };
  }

  CachePolicy _policyForFile(File file) => cachePolicyForPath(file.path);
}

typedef _ShouldApplyToPath = bool Function(String path);

class _PolicyPair {
  _PolicyPair(this.policy, this.shouldApplyToPath);

  final _ShouldApplyToPath shouldApplyToPath;
  final CachePolicy policy;
}
