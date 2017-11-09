# Serving Files and Caching

Aqueduct can serve files by returning the contents of a file as an HTTP response body.

## HTTPFileController

Instances of `HTTPFileController` serve a directory from the filesystem through an HTTP interface. Any route that channels requests to an `HTTPFileController` *must* contain a `*` match-all token.


```dart
@override
Controller get entryPoint {
  final router = new Router();

  router.route("/files/*").pipe(new HTTPFileController("public/"));

  return router;
}
```

The argument to `HTTPFileController` is the directory on the filesystem in which request paths will be resolved against. In the above example, an HTTP request with the path `/files/image.jpg` would return the contents of the file `public/image.jpg`.

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

Adding a leading slash to the directory served by `HTTPFileController` will resolve it relative to the filesystem root.

If the requested path was a directory, the filename `index.html` will be appended to the path when searching for a file to return.

If a file does not exist, an `HTTPFileController` returns a 404 Not Found response.

### Content-Type of Files

An `HTTPFileController` will set the content-type of the HTTP response based on the served files path extension. By default, it recognizes many common extensions like `.html`, `.css`, `.jpg`, `.js`. You may add content-types for extensions to an instance:

```dart
var controller = new HTTPFileController("public/")
  ..setContentTypeForExtension("xml", new ContentType("application", "xml"));
```

If there is no entry for an extension of a file being served, the content-type defaults to `application/octet-stream`. An `HTTPFileController` will never invoke any encoders from `HTTPCodecRepository`, but it will GZIP data if the repository allows compression for the content-type of the file (see `HTTPCodecRepository.add` and `HTTPCodecRepository.setAllowsCompression`).

## Caching

An `HTTPFileController` always sets the the Last-Modified header of the response to the last modified date according to the filesystem. If a request sends an If-Modified-Since header and the file has not been modified since that date, a 304 Not Modified response is sent with the appropriate headers.

You may provide Cache-Control headers depending on the path of the file being served. Here's an example that adds `Cache-Control: public, max-age=31536000`

```dart
var policy = new HTTPCachePolicy(expirationFromNow: new Duration(days: 365));
var controller = new HTTPFileController("public/")
  ..addCachePolicy(policy, (path) => path.endsWith(".css"));
```

## File Serving and Caching Outside of HTTPFileController

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

You may set the `HTTPCachePolicy` of any `Response`. Note that `HTTPCachePolicy` only modifies the Cache-Control header of a response - headers like Last-Modified and ETag are not added.

```dart
var response = new Response.ok("contents")
  ..cachePolicy = new HTTPCachePolicy();
```
