# Request and Response Objects; Serialization

In Aqueduct, HTTP requests and responses are instances of `Request` and `Response`, respectively. For every HTTP request an application receives, an instance of `Request` is created. A `Response` must be created for each `Request`. Requests pass through a channel of [Controllers](controller.md) to be validated, modified and finally responded to.

## The Request Object

An instance of `Request` represents an HTTP request and are automatically created when the application receives a request. A `Request` is a wrapper around the Dart standard library `HttpRequest` and its values - such as its URI or headers - can be accessed through its `raw` property.

A `Request` has a `body` property. This property decodes the body contents into Dart objects based on the request's content type. The mechanism to decode the body is determined by `CodecRegistry`, which is covered in more detail in a later section. By default, decoders exist for text, JSON and form data. The size of a request body is limited to 10MB by default and can be changed by setting the value of `RequestBody.maxSize` during application initialization.

A `Request` is handled by one or more `Controller`s before to be responded to. `Controller`s may validate or add more information to the request, so that later controllers can use this information. For example, an `Authorizer` controller will validate the Authorization header of a request. Once validated, it will add authorization info to the request - like the authorized user ID - and pass it to the next controller. The next controller in the channel has access to the authorization info without having to perform another fetch.

These additional values are added to a `Request.attachments` property. Subsequent controllers can access these values.

```dart
class APIKeyController extends Controller {
  APIKeyController(this.apiService);

  final APIService apiService;

  @override
  Future<RequestOrResponse> handle(Request request) async {
    final apiKey = request.raw.headers.value("x-api-key");
    if (apiKey == null) {
      return Response.badRequest(body: {"error": "missing required header x-api-key"});
    }

    request.attachments["clientId"] = await apiService.getClientId(apiKey);

    return request;
  }
}
```

A `Request` also has two built-in attachments, `authorization` and `path`. `authorization` contains authorization information from an `Authorizer` and `path` has request path information from a `Router`.

`Request`s are responded to when a controller creates a `Response`.

## The Response Object

An instance of `Response` represents the status code, headers and body of an HTTP response. `Response` objects are returned from controller methods like [handle](controller.md) or a [ResourceController operation method](resource_controller.md). Aqueduct sends the contents of a response returned from a controller to the requesting HTTP client. The default constructor takes a status code, header map and body object. There are many named constructors for common response types:

```dart
Response(200, {"x-header": "value"}, body: [1, 2, 3]);
Response.ok({"key": "value"});
Response.created();
Response.badRequest(body: {"error": "reason"});
```

A response can be modified after it is created by middleware controllers. Middleware controllers add *response modifiers* to a `Request`; when the response is created for that request, the modifiers are ran in the order they were added.

```dart
class RequestIdentifyingController extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    // Invoked after another controller in the channel creates a response
    request.addResponseModifier((resp) {      
      resp.headers["x-request-id"] = generateRequestId();
    });

    return request;
  }
}
```

Headers are encoded according to [dart:io.HttpHeaders.add](https://api.dartlang.org/stable/2.0.0/dart-io/HttpHeaders/add.html). For body encoding behavior, see the following sections.

## Encoding and Decoding the HTTP Body

`Request` and `Response` objects have behavior for handling the HTTP body. You decode the contents of a `Request` body into Dart objects that are used in your code. You provide a Dart object to a `Response` and it is automatically encoded according to the content-type of the response.

### Decoding Request Bodies

Every `Request` has a `Request.body` property. This object decodes the bytestream from the request body into Dart objects, and caches that decoded object for subsequent access. The behavior for decoding is determined by the content-type header of the request (see the section on `CodecRegistry` later in this guide). When you decode a body, you can specify the Dart object type you expect it to be. If the decoded body object is not the expected type, an exception that sends a 400 Bad Request error is thrown.

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
    You don't need to provide a type argument to `as` or `decode` if the type can be inferred. For example, `ManagedObject.readFromMap(await request.body.decode())` will infer the type of the decoded body as a `Map<String, dynamic>` without having to provide type parameters.

If a body cannot be decoded according to its content-type (the data is malformed), an error is thrown that sends the appropriate error response to the client. By default, the maximum size of a request body is 10MB (see `RequestBody.maxSize`).

For more request body behavior, see the API reference for `RequestBody`, the [section on body binding for ResourceControllers](resource_controller.md) and a later section in this guide on `Serializable`.

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

The body object must be a valid input for the selected codec. In the above example, a `Map<String, dynamic>` can be encoded by a `JsonCodec`. But if the body object was something silly - like an `Controller` - encoding would fail at runtime and the client would be sent a 500 Server Error response. A valid input for one `Codec` may not be valid for another; it is up to you to ensure that the body object is valid for the `contentType` of the response.

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

Encoding and decoding primarily takes or yields simple Dart objects like `Map`, `List` and `String`. It is often beneficial to add structure to body objects for use in your code. Classes that implement `Serializable` provide this structure. A `Serializable` object must implement a `readFromMap()` and `asMap()` method to convert their structure into or from a Dart `Map`.

An object that implements `Serializable` may be used as a response body object directly:

```dart
class Person implements Serializable {
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

When responding with a `Serializable`, its `asMap()` is called prior to any encoding by the codec registry. `ManagedObject<T>`, part of the Aqueduct ORM, implements `Serializable` so results from `Query<T>` may be body objects:

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

The entire flow of a body object is shown in the following diagram. Each orange item is an allowed body object type and shows the steps it will go through when being encoded to the HTTP response body. For example, a `Serializable` goes through three steps, whereas a `List<int>` goes through zero steps and is added as-is to the HTTP response.

![Response Body Object Flow](../img/response_flow.png)

A serializable object can be read from a request body:

```dart
final person = Person()..readFromMap(await request.body.decode());
```

Serializable objects are the only types of objects that can be [bound to a ResourceController argument](resource_controller.md).

```dart
@Operation.post()
Future<Response> addPerson(@Bind.body() Person person) async {
  final insertedPerson = await Query.insertObject(context, person);
  return Response.ok(insertedPerson);
}
```

### Serializable and OpenAPI Generation

See the section on how `Serializable` types work with OpenAPI documentation generation [here](../openapi/components.md).
