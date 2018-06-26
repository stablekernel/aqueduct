import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

const int numberOfIsolates = 3;

void main() {
  group("Happy path", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("A message sent to the hub is received by other channels, but not by sender", () async {
      app = new Application<HubChannel>()..options.port = 8000;
      await app.start(numberOfInstances: numberOfIsolates);

      var resp = await postMessage("msg1");
      var postingIsolateID = isolateIdentifierFromResponse(resp);
      var id1 = 1;
      var id2 = 2;
      if (postingIsolateID == 1) {
        id1 = 3;
      } else if (postingIsolateID == 2) {
        id2 = 3;
      }

      expect(
          waitForMessages({
            id1: [
              {"isolateID": postingIsolateID, "message": "msg1"}
            ],
            id2: [
              {"isolateID": postingIsolateID, "message": "msg1"}
            ],
          }, butNeverReceiveIn: postingIsolateID),
          completes);
    });

    test("A message sent in prepare is received by all channels eventually", () async {
      app = new Application<HubChannel>()
        ..options.port = 8000
        ..options.context = {"sendIn": "prepare"};
      await app.start(numberOfInstances: numberOfIsolates);

      expect(
          waitForMessages({
            1: [
              {"isolateID": 2, "message": "init"},
              {"isolateID": 3, "message": "init"}
            ],
            2: [
              {"isolateID": 1, "message": "init"},
              {"isolateID": 3, "message": "init"}
            ],
            3: [
              {"isolateID": 2, "message": "init"},
              {"isolateID": 1, "message": "init"}
            ],
          }),
          completes);
    });
  });

  group("Multiple listeners", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Message hub stream can have multiple listeners", () async {
      app = new Application<HubChannel>()
        ..options.port = 8000
        ..options.context = {"multipleListeners": true};
      await app.start(numberOfInstances: numberOfIsolates);

      var resp = await postMessage("msg1");
      var postingIsolateID = isolateIdentifierFromResponse(resp);

      var id1 = 1;
      var id2 = 2;
      if (postingIsolateID == 1) {
        id1 = 3;
      } else if (postingIsolateID == 2) {
        id2 = 3;
      }

      expect(
          waitForMessages({
            id1: [
              {"isolateID": postingIsolateID, "message": "msg1"},
              {"isolateID": postingIsolateID, "message": "msg1"}
            ],
            id2: [
              {"isolateID": postingIsolateID, "message": "msg1"},
              {"isolateID": postingIsolateID, "message": "msg1"}
            ],
          }, butNeverReceiveIn: postingIsolateID),
          completes);
    });
  });

  group("Failure cases", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Send invalid x-isolate data returns error in error stream", () async {
      app = new Application<HubChannel>()..options.port = 8000;
      await app.start(numberOfInstances: numberOfIsolates);

      var resp = await postMessage("garbage");
      var errors = await getErrorsFromIsolates();
      var serverID = isolateIdentifierFromResponse(resp);
      expect(errors[serverID].length, 1);
      expect(errors[serverID].first, contains("Illegal argument in isolate message"));

      // Make sure that we can still send messages from the isolate that encountered the error
      var resendID;
      while (resendID != serverID) {
        resp = await postMessage("ok");
        resendID = isolateIdentifierFromResponse(resp);
      }

      int expectedReceiverID = resendID == 1 ? 2 : 1;
      expect(waitForMessages({
        expectedReceiverID: [{"isolateID": serverID, "message": "ok"}]
      }), completes);
    });
  });
}

Future<http.Response> postMessage(String message) async {
  return http.post("http://localhost:8000/send",
      headers: {HttpHeaders.contentTypeHeader: ContentType.text.toString()}, body: message);
}

Future waitForMessages(Map<int, List<Map<String, dynamic>>> expectedMessages, {int butNeverReceiveIn}) async {
  final response = await http.get("http://localhost:8000/messages");
  final respondingIsolateID = isolateIdentifierFromResponse(response);
  final List<dynamic> messages = json.decode(response.body);

  if (expectedMessages.containsKey(respondingIsolateID)) {
    final remainingMessagesExpectedForIsolateID = expectedMessages[respondingIsolateID];
    for (var message in messages) {
      final firstMatchedMessage = remainingMessagesExpectedForIsolateID.firstWhere((msg) {
        return msg["isolateID"] == message["isolateID"] && msg["message"] == message["message"];
      }, orElse: () => null);

      if (firstMatchedMessage != null) {
        remainingMessagesExpectedForIsolateID.remove(firstMatchedMessage);
        if (remainingMessagesExpectedForIsolateID.length == 0) {
          expectedMessages.remove(respondingIsolateID);
        }
      }
    }
  }

  if (butNeverReceiveIn != null && messages.length > 0 && respondingIsolateID == butNeverReceiveIn) {
    throw new Exception("Received unexpected message from butNeverReceivedIn");
  }

  if (expectedMessages.isNotEmpty) {
    return waitForMessages(expectedMessages, butNeverReceiveIn: butNeverReceiveIn);
  }

  return null;
}

Future<Map<int, List<Map<String, dynamic>>>> getMessagesFromIsolates() async {
  var msgs = <int, List<Map<String, dynamic>>>{};

  while (msgs.length != numberOfIsolates) {
    var resp = await http.get("http://localhost:8000/messages");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = json.decode(resp.body) as List<Map<String, dynamic>>;
    }
  }

  return msgs;
}

Future<Map<int, List<String>>> getErrorsFromIsolates() async {
  var msgs = <int, List<String>>{};

  while (msgs.length != numberOfIsolates) {
    var resp = await http.get("http://localhost:8000/errors");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = new List<String>.from(json.decode(resp.body) as List<String>);
    }
  }

  return msgs;
}

int isolateIdentifierFromResponse(http.Response response) {
  return int.parse(response.headers["server"].split("/").last);
}

class HubChannel extends ApplicationChannel {
  List<Map<String, dynamic>> messages = [];
  List<String> errors = [];

  @override
  Future prepare() async {
    messageHub.listen((event) {
      messages.add(event as Map<String, dynamic>);
    }, onError: (err) {
      errors.add(err.toString());
    });

    if (options.context["multipleListeners"] == true) {
      messageHub.listen((event) {
        messages.add(event as Map<String, dynamic>);
      }, onError: (err) {
        errors.add(err.toString());
      });
    }

    if (options.context["sendIn"] == "prepare") {
      messageHub.add({"isolateID": server.identifier, "message": "init"});
    }
  }

  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/messages").linkFunction((req) async {
      var msgs = new List.from(messages);
      messages = [];
      return new Response.ok(msgs);
    });

    router.route("/errors").linkFunction((req) async {
      var msgs = new List.from(errors);
      errors = [];
      return new Response.ok(msgs);
    });

    router.route("/send").linkFunction((req) async {
      var msg = await req.body.decodeAsString();
      if (msg == "garbage") {
        messageHub.add((x) => x);
      } else {
        messageHub.add({"isolateID": server.identifier, "message": msg});
      }
      return new Response.accepted();
    });
    return router;
  }
}
