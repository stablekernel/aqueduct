# Serializing Request and Response Bodies

In Aqueduct, HTTP requests and responses are instances of `Request`s and `Response`s. For each HTTP request an application receives, an instance of `Request` is created. A `Response` must be created for each request. Responses are created by [controller objects](controller.md). This guide discusses the behavior of request and response objects.

## The Request Object

A `Request` is created for each HTTP request to your application. A `Request` stores everything about the HTTP request and has some additional behavior that makes reading from them easier. You handle requests by writing code in a [controller object](controller.md) or closures.

All properties of a request are available in its `raw` property (a Dart standard library `HttpRequest`). A `Request` has `attachments` that data can be attached to in a controller for use by a linked controller:

```dart
router.route("/path").linkFunction((req) {
  req.attachments["key"] = "value";
}).linkFunction((req) {
  return Response.ok({"key": req.attachments["value"]});
});
```

A `Request` also has two built-in attachments, `authorization` and `path`. `authorization` contains authorization information from an `Authorizer` and `path` has request path information from a `Router`.

## The Response Object

An `Response` has a status code, headers and body. The default constructor takes a status code, header map and body object. There are many named constructors for common response types:

```dart
Response(200, {"x-header": "value"}, body: [1, 2, 3]);
Response.ok({"key": "value"});
Response.created();
Response.badRequest(body: {"error": "reason"});
```

Headers are encoded according to [dart:io.HttpHeaders.add](https://api.dartlang.org/stable/2.0.0/dart-io/HttpHeaders/add.html). For body encoding behavior, see the following sections.

## Encoding and Decoding the HTTP Body

`Request` and `Response` objects have behavior for handling the HTTP body. You decode the contents of a `Request` body into Dart objects that are used in your code. You provide a Dart object to a `Response` and it is automatically encoded according to the content-type of the response.

### Decoding Request Bodies

Every `Request` has a `body` property. This object decodes the bytes from the request body into Dart objects. The behavior for decoding is determined by the content-type header of the request (see the section on `CodecRegistry` later in this guide). When you decode a body, you can specify the Dart object type you expect it to be. If the decoded body object is not the expected type, an exception that sends a 400 Bad Request error is thrown.

```dart
// Ensures that the decoded body is a Map<String, dynamic>
final map = await request.body.decode<Map<String, dynamic>>();

// Takes whatever object the body is decoded into
final anyObject = await request.body.decode();
```

Once a request's body has been decoded, it can be accessed through a synchronous `as` method. This method also takes a type argument to enforce the type of the decoded body object.

```dart
final map = request.body.as<Map<String, dynamic>>();
```

!!! tip "Inferred Types"
    You don't need to provide a type argument to `as` or `decode` if the type can be inferred. For example, `object.read(await request.body.decode())` will infer the type of the decoded body as a `Map<String, dynamic>` without having to provide type parameters.

If a body cannot be decoded according to its content-type (the data is malformed), an error is thrown that sends the appropriate error response to the client.

For more request body behavior, see the API reference for `RequestBody`, the [section on body binding for ResourceControllers](resource_controller.md) and a later section in this guide on `Serializable`.

!!! note "Max Body Size"
      The size of a request body is limited to 10MB by default and can be changed by setting the value of `RequestBody.maxSize` during application initialization.

### Encoding Response Body Objects

An HTTP response often contains a *body*. For example, the body in response to `GET /users/1` might be JSON object that represents a user. To ensure the client understands that the body is a JSON object, it includes the header `Content-Type: application/json; charset=utf-8`.

When creating a `Response` that has a body, you provide a *body object* and a `contentType`. For example:

```dart
var map = {"key": "value"};

// ContentType.json is the default, setting it may be omitted.
// ContentType.json == `application/json; charset=utf-8'
final response = Response.ok(map)
  ..contentType = ContentType.json;
```

Body objects are encoded according to their content-type. In the above, `map` is first encoded as a JSON string and then to a list of UTF8 bytes.

![Map Encoding](../img/object_body_flow.png)

A `ContentType` is made up of three components: a primary type, a subtype and an optional character set.

![Content Type Components](../img/content_type_components.png)

The primary and subtype determine the first conversion step and the charset determines the next. Each step is performed by an instance of `Codec` (from `dart:convert`). For example, the content type `application/json` selects `JsonCodec`, while charset `utf-8` selects `Utf8Codec`. These two codecs are run in succession to convert the `Map` to a list of bytes. The codec is selected by your application's `CodecRegistry`; this is covered in later section.

The body object must be valid for the selected codec. In the above example, a `Map<String, dynamic>` can be encoded by a `JsonCodec`. But if the body object cannot be encoded, a 500 Server Error response is sent. A valid input for one `Codec` may not be valid for another; it is up to you to ensure that the body object is valid for the `contentType` of the response.

Not all content types require two conversion steps. For example, when serving an HTML file, the body object is already an HTML `String`. It will only be converted by a charset encoder:

```dart
var html = "<html></html>";
var response = Response.ok(html)
  ..contentType = ContentType.html;
```

And an image body object needs no conversion at all, since it is already a list of bytes. If there is no registered codec for a content-type, the body object must be a byte array (`List<int>` where each value is between 0-255).

```dart
final imageFile = File("image.jpg");
final imageBytes = await imageFile.readAsBytes();
final response = Response.ok(imageBytes)
  ..contentType = ContentType("image", "jpeg");
```

You may disable the automatic encoding of a body as long as the body object is a byte array:

```dart
final jsonBytes = utf8.encode(json.encode({"key": "value"}));
final response = Response.ok(jsonBytes)..encodeBody = false;
```

See a later section for more details on content type to codec mappings. Also, see the documentation for `CodecRegistry` for details on built-in codecs and adding codecs.

### Streaming Response Bodies

A body object may also be a `Stream<T>`. `Stream<T>` body objects are most often used when serving files. This allows the contents of the file to be streamed from disk to the HTTP client without having to load the whole file into memory first. (See also `FileController`.)

```dart
final imageFile = File("image.jpg");
final imageByteStream = imageFile.openRead();
final response = new Response.ok(imageByteStream)
  ..contentType = new ContentType("image", "jpeg");
```

When a body object is a `Stream<T>`, the response will not be sent until the stream is closed. For finite streams - like those from opened filed - this happens as soon as the entire file is read. For streams that you construct yourself, you must close the stream some time after the response has been returned.

## Codecs and Content Types

In the above sections, we glossed over how a codec gets selected when preparing the response body. The common case of `ManagedObject<T>` body objects that are sent as UTF8 encoded JSON 'just works' and is suitable for most applications. When serving assets for a web application or different data formats like XML, it becomes important to understand how Aqueduct's codec registry works.

`CodecRegistry` contains mappings from content types to `Codec`s. These codecs encode response bodies and decode request bodies. There are three built-in codecs for `application/json`, `application/x-www-form-urlencoded` and `text/*`. When a response is being sent, the repository is searched for an entry that exactly matches the primary and subtype of the `Response.contentType`. If an entry exists, the associated `Codec` starts the conversion. For example, if the content type is `application/json; charset=utf-8`, the built-in `application/json` codec encodes the body object.

If there isn't an exact match, but there is an entry for the primary type with the wildcard (`*`) subtype, that codec is used. For example, the built-in codec for `text/*` will be selected for both `text/plain` and `text/html`. If there was something special that had to be done for `text/html`, a more specific codec may be added for that type:

```dart
class MyChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    CodecRegistry.defaultInstance.add(ContentType("application", "html"), HTMLCodec());
  }
}
```

Codecs must be added in your `ApplicationChannel.prepare` method. The codec must implement `Codec` from `dart:convert`. In the above example, when a response's content type is `text/html`, the `HTMLCodec` will encode the body object. This codec takes precedence over `text/*` because it is more specific.

When selecting a codec for a response body, the `ContentType.charset` doesn't impact which codec is selected. If a response's content-type has a charset, then a charset encoder like `UTF8` will be applied as a last encoding step. For example, a response with content-type `application/json; charset=utf-8` will encode the body object as a JSON string, which is then encoded as a list of UTF8 bytes. It is required that a response body's eventually encoded type is a list of bytes, so it follows that a codec that produces a string must have a charset.

If there is no codec in the repository for the content type of a `Response`, the body object must be a `List<int>` or `Stream<List<int>>`. If you find yourself converting data prior to setting it as a body object, it may make sense to add your own codec to `CodecRegistry`.

A request's body always starts as a list of bytes and is decoded into Dart objects. To decode a JSON request body, it first must be decoded from the list of UTF8 bytes into a string. It is possible that a client could omit the charset in its content-type header. Codecs added to `CodecRegistry` may specify a default charset to interpret a charset-less content-type. When a codec is added to the repository, if content-type's charset is non-null, that is the default. For example, the JSON codec is added like this:

```dart
CodecRegistry.defaultInstance.add(
  ContentType("application", "json", charset: "utf-8"),
  const JsonCodec(),
  allowCompression: true);
```

If no charset is specified when registering a codec, no charset decoding occurs on a request body if one doesn't exist. Content-types that are decoded from a `String` should not use a default charset because the repository would always attempt to decode the body as a string first.

### Compression with gzip

Body objects may be compressed with `gzip` if the HTTP client allows it *and* the `CodecRegistry` has been configured to compress the content type of the response. The three built-in codecs - `application/json`, `application/x-www-form-urlencoded` and `text/*` - are all configured to allow compression. Compression occurs as the last step of conversion and only if the HTTP client sends the `Accept-Encoding: gzip` header.

Content types that are not in the codec repository will not trigger compression, even if the HTTP client allows compression with the `Accept-Encoding` header. This is to prevent binary contents like images from being 'compressed', since they are likely already compressed by a content-specific algorithm. In order for Aqueduct to compress a content type other than the built-in types, you may add a codec to the repository with the `allowCompression` flag. (The default value is `true`.)

```dart
CodecRegistry.add(
  ContentType("application", "x-special"),
   MyCodec(),
  allowCompression: true);
```

You may also set whether or not a content type uses compression without having to specify a codec if no conversion step needs to occur:

```dart
CodecRegistry.setAllowsCompression(new ContentType("application", "x-special"), true);
```

## Serializable Objects

Most request and response bodies are JSON objects and lists of objects. In Dart, JSON objects are maps. A `Serializable` object can be read from a map and converted back into a map. You subclass `Serializable` to assign keys from a map to properties of a your subclass, and to write its properties back to a map. This allows static types you declare in your application to represent expected request and response bodies. Aqueduct's ORM type `ManagedObject` is a `Serializable`, for example.

### Sending Serializable Objects as Response Bodies

The body object of a response can be a `Serializable`. Before the response is sent, `asMap()` is called before the body object is encoded into JSON (or some other transmission format).

For example, a single serializable object returned in a 200 OK response:

```dart
final query = Query<Person>(context)..where((p) => p.id).equalTo(1);
final person = await query.fetchOne();
final response = Response.ok(person);
```

A response body object can also be a list of `Serializable` objects.

```dart
final query = Query<Person>(context);
final people = await query.fetch();
final response = Response.ok(people);
```

The flow of a body object is shown in the following diagram. Each orange item is an allowed body object type and shows the steps it will go through when being encoded to the HTTP response body. For example, a `Serializable` goes through three steps, whereas a `List<int>` goes through zero steps and is added as-is to the HTTP response.

![Response Body Object Flow](../img/response_flow.png)

### Reading Serializable Objects from Request Bodies

A serializable object can be read from a request body:

```dart
final person = Person()..read(await request.body.decode());
```

A list of serializable objects as well:

```dart
List<Map<String, dynamic>> objects = await request.body.decode();
final people = objects.map((o) => Person()..read(o)).toList();
```


Both serializable and a list of serializable can be [bound to a operation method parameter in a ResourceController](resource_controller.md).

```dart
@Operation.post()
Future<Response> addPerson(@Bind.body() Person person) async {
  final insertedPerson = await context.insertObject(person);
  return Response.ok(insertedPerson);
}
```

#### Key Filtering

Both `read` and `Bind.body` (when binding a `Serializable`) support key filtering. A key filter is a list of keys that either discard keys from the body, requires keys in the body, or throws an error if a key exists in the body. Example:

```dart
final person = Person()
  ..read(await request.body.decode(),
         ignore: ["id"],
         reject: ["password"],
         require: ["name", "height", "weight"]);
```

In the above: if the body contains 'id', the value is discarded immediately; if the body contains 'password', a 400 status code exception is thrown; and if the body doesn't contain all of name, height and weight, a 400 status code exception is thrown.

When binding a list of serializables, filters are applied to each element of the list.

```dart
@Operation.post()
Future<Response> addPerson(@Bind.body(reject: ["privateInfo"]) List<Person> people) async {
  // if any Person in the body contains the privateInfo key, a 400 Bad Request is sent and this method
  // is not called
}
```

### Subclassing Serializable

A `Serializable` object must implement a `readFromMap()` and `asMap()`.

An object that extends `Serializable` may be used as a response body object directly:

```dart
class Person extends Serializable {
  String name;
  String email;

  Map<String, dynamic> asMap() {
    return {
      "name": name,
      "email": email
    };
  }

  void readFromMap(Map<String, dynamic> inputMap) {
    name = inputMap['name'];
    email = inputMap['email'];
  }
}

final person = Person();
final response = Response.ok(person);
```

`readFromMap` is invoked by `read`, after all filters have been applied.

### Serializable and OpenAPI Generation

See the section on how `Serializable` types work with OpenAPI documentation generation [here](../openapi/components.md).
