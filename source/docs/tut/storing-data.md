# 3. Storing Data in a Database

In the previous exercise, we loaded some heroes into the database our application reads from. Now, we will allow our application to store, delete and modify heroes in the database. Before we embark on this part of the journey, it's important that we understand how an HTTP API is intended to work.

## HTTP Resources and Methods

The [HTTP specification](https://tools.ietf.org/html/rfc7231) defines the concept of a *resource*. A resource can be anything - a hero, a bank account, a light switch in your home, a temperature sensor in Antarctica, etc. Some of these things are physical objects (the light switch), and some are digital - and they are all resources. An HTTP server application is an interface to these resources; a client requests that something be done with a resource, and the server finds a way to get it done.

Resources are identified with a URI. A URI *universally identifies* a resource: it has the address of a server to connect to, and a path that identifies the resource on that server. When writing Aqueduct applications, we don't care much about the server part of a URL - the internet figures out that part. What we do care about is the path of the URL - like `/heroes`.

An application uses the URL path to determine which resource the request wants to work with. Right now, our application works with hero resources. A request with the path `/heroes/1` wants to do something with an individual hero (that is identified by the number `1`). A request with the path `/heroes` will act on the entire collection of heroes.

These actions are primarily described by the request method (like GET, POST, OR DELETE). Each of these methods has a general meaning that describes an action that can be applied to a resource. For example, a `GET /heroes` means "get me all of the hero resources". The meaning for each of these methods are as follows:

- GET: returns a collection of some resource or an individual resource
- POST: inserts or appends a resource to a collection of some resource; a representation of the resource is in the request body
- PUT: replaces a resource with the contents of the request body (or in some cases, replaces the entire collection of some resource)
- DELETE: deletes a resource (or in some cases, deletes the entire collection of some resource)

It turns out, we can create a lot of incredible behavior by just combining these methods and a request path. More importantly, by following these specifications, client applications can use generic libraries to access any HTTP API with very little effort. This allows us to create complex systems that are easily made available to a browser, mobile phone or any other internet-connected device.

## Inserting Data

We'll start by adding behavior that allows for new heroes to be inserted into the database. Following our previous discussion, the HTTP request must take the form `POST /heroes` - we are appending a new hero to the collection of heroes. This request will contain the JSON representation of a hero in its body, for example:

```json
{
  "name": "Master of Aqueducts"
}
```

Our `HeroesController` will handle this operation. In general, a single endpoint controller should handle every operation on a resource collection and its individual resources. In `heroes_controller.dart`, add the following operation method:

```dart
@Operation.post()
Future<Response> createHero() async {
  final Map<String, dynamic> body = await request.body.decode();
  final query = Query<Hero>(context)
    ..values.name = body['name'] as String;

  final insertedHero = await query.insert();

  return Response.ok(insertedHero);
}
```

There's three important things happening here: this method decodes the JSON object from the request's body, constructs a query that inserts a new hero with the name in the JSON object, and then returns the newly inserted hero in the response.

If the decoded body doesn't match the type of the variable or parameter it is being assigned to, a status code 400 exception is thrown. This means that decoding the body in this way checks that the body is the expected format and returns an error to the client on your behalf if it is not. For example, if someone posts a list of JSON objects, they will get a 400 Bad Request response because we expect a single JSON object in our method.

An insertion query sets the properties of its `values` object. The `values` object is an instance of the type being inserted. Invoking `insert` on a query inserts a row with its values. A new hero, with its primary key set by the database, is returned and returned as the body of the response. The generated SQL for the above would be something like:

```sql
INSERT INTO _Hero (name) VALUES ('Hero Name');
```

!!! tip "Column Attributes"
    The `id` of a hero is automatically generated because of its `@primaryKey` annotation. This annotation is a `Column` that configures the id to be both a primary key and be 'auto-incrementing'. Auto-incremented columns values are generated automatically (1, 2, 3...). See [the API reference for Column](https://www.dartdocs.org/documentation/aqueduct/latest/aqueduct/Column-class.html) for column options.

Re-run your application. In the browser application, click on `Heroes` near the top of the page. Then, enter a name into the `Hero name:` field and click `Add`. The new hero will appear. You can re-run the application and that hero will still be available, because it has been stored in the database on your machine.

![Insert Hero](../img/run3.png)

Assigning values one-by-one from a request body to a query is cumbersome. You can also auto-magically ingest a request body into a managed object and assign it to the `values` of a query:

```dart
@Operation.post()
Future<Response> createHero() async {
  final hero = Hero()
    ..read(await request.body.decode(), ignore: ["id"]);
  final query = Query<Hero>(context)..values = hero;

  final insertedHero = await query.insert();

  return Response.ok(insertedHero);
}
```

The `read` method reads a `Map<String, dynamic>` into a managed object. Each key's value is assigned to the property of the same name. The `ignore:` optional parameter removes values for that key from the map before reading it. You can also reject or require keys in this way. If a request body contains a key that isn't declared as property of the managed object, a 400 status code exception is thrown.

!!! tip "Sub-resources"
    We mentioned that a single controller should handle every operation for a resource collection and its individual resources. Some resources are complex enough that they can have sub-resources. For example, an organization of heroes (like the X-Men or Fantastic Four) contains heroes, but it might also contain buildings and equipment owned by the organization. The heroes, buildings and equipment are sub-resources of an organization.  Each sub-resource should have its own route and controller instead of trying to shove everything into a single route and controller. See the following code snippet for an example.

```dart
@override
Controller get entryPoint {
  return Router()
    ..route("/organizations/[:orgName]")
      .link(() => OrganizationController());
    ..route("/organizations/:orgName/heroes/[:heroID]")
      .link(() => OrgHeroesController());
    ..route("/organizations/:orgName/buildings/[:buildingID]")
      .link(() => OrgBuildingController());
}
```    

## Request and Response Bodies

So far, we've largely glossed over how request and response bodies are handled, and now is a good time to dig in to this topic.

### Response Body Encoding

When we create a response, we specify its status code and optionally its headers and body. For example, the following creates a response with a status code of 200 OK with an empty list body:

```dart
Response.ok([])
```

The first argument to `Response.ok` is a *body object*. A body object is automatically encoded according to the `contentType` of its response. By default, the content type of a response is `application/json` - so by default, all of our response body objects are JSON-encoded in the response body.

!!! note "Other Response Constructors"
    The default constructor for a `Response` takes a status code, map of headers and a body object: `Response(200, {}, "body")`. There are many named constructors for `Response`, like `Response.ok` or `Response.notFound`. These constructors set the status code and expose parameters that are intended for that type of response. For example, a 200 OK response should have a body, so `Response.ok` has a required body object argument. See [the API reference for Response](https://www.dartdocs.org/documentation/aqueduct/latest/aqueduct/Response-class.html) for possible constructors and properties of a response.

To change the format a body object is encoded into, you set the `contentType` of the response. For example,

```dart
Response.ok([])
  ..contentType = new ContentType("application", "xml");
```

The default supported content types are JSON, `application/x-www-form-urlencoded` and all `text/*` types. To encode other content-types, you must register a `Codec` with `CodecRegistry.` A body object is only valid if the codec selected by the response's content-type can encode it. If it can't, an error will be thrown and a 500 Server Error response is sent instead.

Types that implement `Serializable` may also be body objects. Objects that implement this type provide an `asMap()` method that converts their properties into a `Map` before being passed to the encoder. This `Map` must be encodable for the response's content-type codec. You may also provide a `List` of `Serializable`, for which the list of each object's `asMap()` is passed to the encoder.

`ManagedObject` implements the `Serializable` interface, and therefore all managed objects (and lists of managed objects) can be body objects.

### Request Body Decoding

Every `Request` has a `body` property of type `RequestBody`. A `RequestBody` decodes the contents of the request body into Dart objects that you use in your application. This decoding is performed by the `Codec` that is associated with the request's content-type. The decoded object is determined by the format of the data - for example, a JSON array decodes into a `List`, a JSON object into a `Map`.

When you write code to decode a request body, you are also validating the request body is in the expected format. For example, your `HeroesController` invokes `decode` like this:

```dart
Map<String, dynamic> body = await request.body.decode();
```

The `decode` method has a type argument that is inferred to be a `Map<String, dynamic>`. If the decoded body is not a `Map`, an exception is thrown that sends an appropriate error response to the client.

You may also bind the body of a request to an operation method parameter. Let's bind a `Hero` instance to a request body in our `HeroesController`. Update the code in that file to the following:

```dart
@Operation.post()
Future<Response> createHero(@Bind.body(ignore: ["id"]) Hero inputHero) async {
  final query = Query<Hero>(context)
    ..values = inputHero;

  final insertedHero = await query.insert();

  return Response.ok(insertedHero);
}
```

Values in the request body object are decoded into a `Hero` object - each key in the request body maps to a property of our `Hero`. For example, the value for the key 'name' is stored in the `inputHero.name`. If decoding the request body into a `Hero` instance fails for any reason, a 400 Bad Request response is sent and the operation method is not called.

!!! tip "Binding Serializables"
        A body can be bound to any type - a request will only succeed if the decoded body matches the expected type. When a `Serializable` subclass (or `List<Serializable>`) is bound to a body, it enforces the body to be decoded into a `Map<String, dynamic>` (or a `List<Map<String, dynamic>>`). All `ManagedObject`s implement `Serializable`, and therefore you may bind managed objects (and lists of such) using body binding.

Re-run your `heroes` application. On [http://aqueduct-tutorial.stablekernel.io](http://aqueduct-tutorial.stablekernel.io), click on the `Heroes` button on the top of the screen. In the text field, enter a new hero name and click `Add`. You'll see your new hero added to the list! You can shutdown your application and run it again and you'll still be able to fetch your new hero.

![Aqueduct Tutorial Third Run](../img/run3.png)

!!! tip "Query Construction"
    Properties like `values` and `where` prevent errors by type and name checking columns with the analyzer. They're also great for speeding up writing code because your IDE will autocomplete property names. There is [specific behavior](../db/advanced_queries.md) a query uses to decide whether it should include a value from these two properties in the SQL it generates.

## [Next Chapter: Writing Tests](writing-tests.md)
