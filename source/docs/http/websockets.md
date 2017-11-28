# Using Websockets in Aqueduct

A standard HTTP request will yield an HTTP response from a web server. In order for the server to send data to a client, the client must have sent a request for that data. A *websocket* is a special type of HTTP request that stays open, and both the server and client can send data to one another whenever they please.

For example, a chat application might use websockets to send messages to everyone in a chatroom. In this scenario, the chat client application opens a websocket connection to the server application. When the user types a message, their chat client sends that message on its websocket. The payload might be JSON data that looks like this:

```json
{
  "action": "send_message",
  "room": "general",
  "text": "Hi everyone"
}
```

The server will receive this data, then turn around and send a modified version to *every* websocket connection it has. That data might look like this:

```json
{
  "action": "receive_message",
  "room": "general",
  "from": "Bob",
  "text": "Hi everyone"
}
```

Every connected user will receive this data and draw `Bob: Hi everyone` to the screen.

Note that there's nothing about websockets that says you have to use JSON data - you can use any data format you like.

## Upgrading an HTTP Request to a WebSocket

In Aqueduct, websockets are handled by Dart's standard library `WebSocket` type. Here's an example:

```dart
router
  .route("/connect")
  .listen((request) async {
    var socket = await WebSocketTransformer.upgrade(request.raw);
    socket.listen(listener);

    return null;
  });
```

It's important that a request that is upgraded to a websocket is removed from the channel by returning null from the controller. (See the section on `Aqueduct and dart:io` [in this guide](structure.md) for more details.)

A client application can connect to the URL `ws://localhost:8888/connect`. A Dart application would make this connection like so:

```dart
var socket = await WebSocket.connect("ws://localhost:8888/connect");
socket.listen(...);
```

## Bi-directional Communication

In the simple example above, the server only listens for data from the client. For data to be sent to the client, a reference must be kept to the `WebSocket` so that data can be added to it. How an Aqueduct application manages its websocket connections depends greatly on the behavior of the application, the number of isolates the application is running on and the infrastructure of the system as a whole.

A simple application might keep track of websocket connections in a `Map`, where the key is a user identifier acquired from the authorization of the request:

```dart
router
  .route("/connect")
  .pipe(new Authorizer(authServer));
  .listen((request) async {
    var userID = request.authorization.resourceOwnerIdentifier;
    var socket = await WebSocketTransformer.upgrade(request.raw);
    socket.listen((event) => handleEvent(event, fromUserID: userID));

    connections[userID] = socket;

    return null;
  });
```

If we continue with the 'chat application' example, the code for `handleEvent` may be something like:

```dart
void handleRequest(dynamic event, {int fromUserID}) {
  var incoming = JSON.decode(UTF8.decode(event));
  var outgoing = UTF8.encode(JSON.encode({
    "text": incoming["text"],
    ...
  }));

  connections.keys
    .where((userID) => userID != fromUserID)
    .forEach((userID) {
      var connection = connections[userID];
      connection.add(outgoing);
    });        
}
```

Note that this simple implementation doesn't account for multiple connections from the same user or multi-isolate applications.

## Considerations for Multi-Isolate and Multi-Instance Applications

By default, an Aqueduct application runs on multiple isolates. Since each isolate has its own heap, a websocket created on one isolate is not directly accessible by another isolate. In the example above, each isolate would have its own map of connections - therefore, a message is only sent to connections that were opened on the same isolate that the chat message originated from.

A simple solution is to only run the application on a single isolate, ensuring that all websockets are on a single isolate and accessible to one another:

```dart
aqueduct serve -n 1
```

For many applications, this is a fine solution. For others, it may not be.

Recall that one of the benefits of Aqueduct's multi-isolate architecture is that code tested on a single instance will scale to multiple instances behind a load balancer. If an Aqueduct application runs correctly on a single, multi-isolate instance, it will will correctly on multiple instances. This (somewhat) enforced structure prevents us from naively keeping track of websocket connections on a single isolate, which would cause issues when we scale out to a multi-instance system.

If you find yourself in a situation where your application is so popular you need multiple servers to efficiently serve requests, you'll have a good idea on how to architect an appropriate solution (or you'll have the money to hire someone that does). In many situations, the REST API and websocket server are separate instances anyhow - they have different lifecycles and deployment behavior. It may make sense to run a websocket server on a single isolate, since you are likely IO-bound instead of CPU bound.

If you still prefer to have a multi-isolate server with websockets, the `ApplicationMessageHub` will come in handy. When broadcasting messages to connected websockets across the application, you first send the data to each websocket connected to the isolate that is originating the message. Then, the message is added to the `ApplicationMessageHub`:

```dart
void onChatMessage(String message) {
  connectedSockets.forEach((socket) {
    socket.add(message);
  });

  ApplicationChannel.messageHub.add({"event": "websocket_broadcast", "message": message});
}
```

Anything added to the `messageHub` will be delivered to the listener for every other message hub - i.e., every other isolate will receive this data. The other isolates then send the message to each of their connected websockets:

```dart
class ChatChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    messageHub.listen((event) {
      if (event is Map && event["event"] == "websocket_broadcast") {
        connectedSockets.forEach((socket) {
          socket.add(event["message"]);
        });
      }
    });
  }
}
```
