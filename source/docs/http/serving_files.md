# Serving Files and Caching

Aqueduct can serve files by returning the contents of a file as an HTTP response body.

## FileController

Instances of `FileController` serve a directory from the filesystem through an HTTP interface. Any route that channels requests to an `FileController` *must* contain a `*` match-all token.


```dart
@override
Controller get entryPoint {
  final router = new Router();

  router.route("/files/*").link(() => new FileController("public/"));

  return router;
}
```

The argument to `FileController` is the directory on the filesystem in which request paths will be resolved against. In the above example, an HTTP request with the path `/files/image.jpg` would return the contents of the file `public/image.jpg`.

Note that `public/` does not have a leading slash - therefore, the directory `public` must be relative to the directory that the Aqueduct application was served from. In practice, this means you might have a directory structure like:

```
project/
  pubspec.yaml  
  lib/
    channel.dart
    ...
  test/
    ...
  public/
    image.jpg
```

Adding a leading slash to the directory served by `FileController` will resolve it relative to the filesystem root.

If the requested path was a directory, the filename `index.html` will be appended to the path when searching for a file to return.

If a file does not exist, an `FileController` returns a 404 Not Found response.

### Content-Type of Files

An `FileController` will set the content-type of the HTTP response based on the served files path extension. By default, it recognizes many common extensions like `.html`, `.css`, `.jpg`, `.js`. You may add content-types for extensions to an instance:

```dart
var controller = new FileController("public/")
  ..setContentTypeForExtension("xml", new ContentType("application", "xml"));
```

If there is no entry for an extension of a file being served, the content-type defaults to `application/octet-stream`. An `FileController` will never invoke any encoders from `CodecRegistry`, but it will GZIP data if the repository allows compression for the content-type of the file (see `CodecRegistry.add` and `CodecRegistry.setAllowsCompression`).

## Caching

An `FileController` always sets the the Last-Modified header of the response to the last modified date according to the filesystem. If a request sends an If-Modified-Since header and the file has not been modified since that date, a 304 Not Modified response is sent with the appropriate headers.

You may provide Cache-Control headers depending on the path of the file being served. Here's an example that adds `Cache-Control: public, max-age=31536000`

```dart
var policy = new CachePolicy(expirationFromNow: new Duration(days: 365));
var controller = new FileController("public/")
  ..addCachePolicy(policy, (path) => path.endsWith(".css"));
```

## File Serving and Caching Outside of FileController

A file can be served by any controller by setting the body object of a `Response` with its contents:

```dart
var file = new File("index.html");

// By loading contents into memory first...
var response = new Response.ok(file.readAsStringSync())
  ..contentType = new ContentType("application", "html");

// Or by streaming the contents from disk
var response = new Response.ok(file.openRead())
  ..encodeBody = false
  ..contentType = new ContentType("application", "html");
```

It is important to understand the how Aqueduct [uses content-types to manipulate response bodies](request_and_response.md) to serve file contents.

You may set the `CachePolicy` of any `Response`. Note that `CachePolicy` only modifies the Cache-Control header of a response - headers like Last-Modified and ETag are not added.

```dart
var response = new Response.ok("contents")
  ..cachePolicy = new CachePolicy();
```
