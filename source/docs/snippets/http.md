# Aqueduct HTTP Snippets

## Hello, World

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = Router();

    router.route("/hello_world").linkFunction((request) async {
      return Response.ok("Hello, world!")
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
    final router = Router();

    router.route("/variable/[:variable]").linkFunction((request) async {
      return Response.ok({
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
    final router = Router();

    router
      .route("/users/[:id]")
      .link(() => MyController());

    return router;
  }
}

class MyController extends ResourceController {
  final List<String> things = ['thing1', 'thing2'];

  @Operation.get()
  Future<Response> getThings() async {
    return Response.ok(things);
  }

  @Operation.get('id')
  Future<Response> getThing(@Bind.path('id') int id) async {
    if (id < 0 || id >= things.length) {
      return Response.notFound();
    }
    return Response.ok(things[id]);
  }
}
```

## Custom Middleware

```dart
class AppChannel extends ApplicationChannel {  
  @override
  Controller get entryPoint {
    final router = Router();

    router
      .route("/rate_limit")
      .link(() => RateLimiter())
      .linkFunction((req) async => Response.ok({
        "requests_remaining": req.attachments["remaining"]
      }));

    return router;
  }
}

class RateLimiter extends RequestController {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    final apiKey = request.raw.headers.value("x-apikey");
    final requestsRemaining = await remainingRequestsForAPIKey(apiKey);
    if (requestsRemaining <= 0) {
      return Response(429, null, null);
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
    final router = Router();

    router.route("/things").linkFunction((request) async {
      return Response.ok(["Widget", "Doodad", "Transformer"]);
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
    final router = Router();

    router.route("/files/*").link(() =>
      FileController("web")
        ..addCachePolicy(new CachePolicy(expirationFromNow: new Duration(days: 365)),
          (path) => path.endsWith(".js") || path.endsWith(".css"))      
    );

    return router;
  }
}
```

## Streaming Responses (Server Side Events with text/event-stream)

```dart
class AppChannel extends ApplicationChannel {
    final StreamController<String> controller = StreamController<String>.broadcast();  

  @override
  Future prepare() async {
    var count = 0;
     Timer.periodic(new Duration(seconds: 1), (_) {
      count ++;
      controller.add("This server has been up for $count seconds\n");
    });
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    router.route("/stream").linkFunction((req) async {
      return Response.ok(controller.stream)
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
    final router = Router();

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
  final ContentType CSV = ContentType("text", "csv", charset: "utf-8");

  @override
  Future prepare() async {
    // CsvCodec extends dart:convert.Codec
    CodecRegistry.defaultInstance.add(CSV, new CsvCodec());
  }

  @override
  Controller get entryPoint {
    final router = Router();

    router.route("/csv").linkFunction((req) async {
      // These values will get converted by CsvCodec into a comma-separated string
      return Response.ok([[1, 2, 3], ["a", "b", "c"]])
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
    final router = Router();

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
