# Aqueduct HTTP Snippets

## Hello, World

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/hello_world").linkFunction((request) async {
      return new Response.ok("Hello, world!")
        ..contentType = ContentType.TEXT;
    });

    return router;
  }
}
```

## Route Variables

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/variable/[:variable]").linkFunction((request) async {
      return new Response.ok({
        "method": request.raw.method,
        "path": request.path.variables["variable"] ?? "not specified"
      });      
    });

    return router;
  }
}
```

## Grouping Routes and Binding Path Variables

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/users/[:id]")
      .link(() => new Controller());

    return router;
  }
}

class Controller extends RESTController {
  final List<String> things = const ['thing1', 'thing2'];

  @Operation.get()
  Future<Response> getThings() async {
    return new Response.ok(things);
  }

  @Operation.get('id')
  Future<Response> getThing(@Bind.path('id') int id) async {
    if (id < 0 || id >= things.length) {
      return new Response.notFound();
    }
    return new Response.ok(things[id]);
  }
}
```

## Custom Middleware

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/rate_limit")
      .link(() => new RateLimiter())
      .linkFunction((req) async => new Response.ok({
        "requests_remaining": req.attachments["remaining"]
      }));

    return router;
  }
}

class RateLimiter extends RequestController {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    var apiKey = request.raw.headers.value("x-apikey");
    var requestsRemaining = await remainingRequestsForAPIKey(apiKey);
    if (requestsRemaining <= 0) {
      return new Response(429, null, null);
    }

    request.addResponseModifier((r) {
      r.headers["x-remaining-requests"] = requestsRemaining;
    });

    return request;
  }
}

```

## Application-Wide CORS Allowed Origins

```dart
class AppChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    // All controllers will use this policy by default
    CORSPolicy.defaultPolicy.allowedOrigins = ["https://mywebsite.com"];
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/things").linkFunction((request) async {
      return new Response.ok(["Widget", "Doodad", "Transformer"]);
    });

    return router;
  }
}
```

## Serve Files and Set Cache-Control Headers

```dart
class AppChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/files/*").link(() =>
      new HTTPFileController("web")
        ..addCachePolicy(new HTTPCachePolicy(expirationFromNow: new Duration(days: 365)),
          (path) => path.endsWith(".js") || path.endsWith(".css"))      
    );

    return router;
  }
}
```

## Streaming Responses (Server Side Events with text/event-stream)

```dart
class AppChannel extends ApplicationChannel {
  final StreamController<String> controller = new StreamController<String>();  

  @override
  Future prepare() async {
    var count = 0;
    new Timer.periodic(new Duration(seconds: 1), (_) {
      count ++;
      controller.add("This server has been up for $count seconds\n");
    });
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/stream").linkFunction((req) async {
      return new Response.ok(controller.stream)
          ..bufferOutput = false
          ..contentType = new ContentType(
            "text", "event-stream", charset: "utf-8");
    });

    return router;
  }
}
```

## A websocket server

```dart
class AppChannel extends ApplicationChannel {
  List<WebSocket> websockets = [];

  @override
  Future prepare() async {
    // When another isolate gets a websocket message, echo it to
    // websockets connected on this isolate.
    messageHub.listen(sendBytesToConnectedClients);
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    // Allow websocket clients to connect to ws://host/connect
    router.route("/connect").linkFunction((request) async {
      var websocket = await WebSocketTransformer.upgrade(request.raw);
      websocket.listen(echo, onDone: () {
        websockets.remove(websocket);
      }, cancelOnError: true);
      websockets.add(websocket);

      // Take request out of channel
      return null;
    });

    return router;
  }

  void sendBytesToConnectedClients(List<int> bytes) {
    websockets.forEach((ws) {
      ws.add(bytes);
    });
  }

  void echo(List<int> bytes) {
    sendBytesToConnectedClients(bytes);

    // Send to other isolates
    messageHub.add(bytes);
  }
}
```

## Setting Content-Type and Encoding a Response Body

```dart
class AppChannel extends ApplicationChannel {
  final ContentType CSV = new ContentType("text", "csv", charset: "utf-8");

  @override
  Future prepare() async {
    // CsvCodec extends dart:convert.Codec
    HTTPCodecRepository.defaultInstance.add(CSV, new CsvCodec());
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/csv").linkFunction((req) async {
      // These values will get converted by CsvCodec into a comma-separated string
      return new Response.ok([[1, 2, 3], ["a", "b", "c"]])
        ..contentType = CSV;
    });

    return router;
  }
}

```

## Proxy a File From Another Server

```dart
class AppChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/proxy/*").linkFunction((req) async {
      var fileURL = "https://otherserver/${req.path.remainingPath}";
      var fileRequest = await client.getUrl(url);
      var fileResponse = await req.close();
      if (fileResponse.statusCode != 200) {
        return new Response.notFound();
      }

      // A dart:io.HttpResponse is a Stream<List<int>> of its body bytes.
      return new Response.ok(fileResponse)
        ..contentType = fileResponse.headers.contentType
        // let the data just pass through because it has already been encoded
        // according to content-type; applying encoding again would cause
        // an issue
        ..encodeBody = false;
    });

    return router;
  }
}
```
