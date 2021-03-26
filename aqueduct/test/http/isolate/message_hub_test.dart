import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Happy path", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test(
        "A message sent to the hub is received by other channels, but not by sender",
        () async {
      app = Application<HubChannel>()..options.port = 8000;
      await app.start(numberOfInstances: 3);

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

    test("A message sent in prepare is received by all channels eventually",
        () async {
      app = Application<HubChannel>()
        ..options.port = 8000
        ..options.context = {"sendIn": "prepare"};
      await app.start(numberOfInstances: 3);

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
      app = Application<HubChannel>()
        ..options.port = 8000
        ..options.context = {"multipleListeners": true};
      await app.start(numberOfInstances: 3);

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
      app = Application<HubChannel>()..options.port = 8000;
      await app.start(numberOfInstances: 3);

      var resp = await postMessage("garbage");
      var errors = await getErrorsFromIsolates();
      var serverID = isolateIdentifierFromResponse(resp);
      expect(errors[serverID].length, 1);
      expect(errors[serverID].first,
          contains("Illegal argument in isolate message"));

      // Make sure that we can still send messages from the isolate that encountered the error
      dynamic resendID;
      while (resendID != serverID) {
        resp = await postMessage("ok");
        resendID = isolateIdentifierFromResponse(resp);
      }

      int expectedReceiverID = resendID == 1 ? 2 : 1;
      expect(
          waitForMessages({
            expectedReceiverID: [
              {"isolateID": serverID, "message": "ok"}
            ]
          }),
          completes);
    });
  });
}

Future<http.Response> postMessage(String message) async {
  return http.post("http://localhost:8000/send",
      headers: {HttpHeaders.contentTypeHeader: ContentType.text.toString()},
      body: message);
}

Future waitForMessages(Map<int, List<Map<String, dynamic>>> expectedMessages,
    {int butNeverReceiveIn}) async {
  final response = await http.get("http://localhost:8000/messages");
  final respondingIsolateID = isolateIdentifierFromResponse(response);
  final messages = json.decode(response.body) as List<dynamic>;

  if (expectedMessages.containsKey(respondingIsolateID)) {
    final remainingMessagesExpectedForIsolateID =
        expectedMessages[respondingIsolateID];
    for (var message in messages) {
      final firstMatchedMessage =
          remainingMessagesExpectedForIsolateID.firstWhere((msg) {
        return msg["isolateID"] == message["isolateID"] &&
            msg["message"] == message["message"];
      }, orElse: () => null);

      if (firstMatchedMessage != null) {
        remainingMessagesExpectedForIsolateID.remove(firstMatchedMessage);
        if (remainingMessagesExpectedForIsolateID.isEmpty) {
          expectedMessages.remove(respondingIsolateID);
        }
      }
    }
  }

  if (butNeverReceiveIn != null &&
      messages.isNotEmpty &&
      respondingIsolateID == butNeverReceiveIn) {
    throw Exception("Received unexpected message from butNeverReceivedIn");
  }

  if (expectedMessages.isNotEmpty) {
    return waitForMessages(expectedMessages,
        butNeverReceiveIn: butNeverReceiveIn);
  }

  return null;
}

Future<Map<int, List<Map<String, dynamic>>>> getMessagesFromIsolates() async {
  var msgs = <int, List<Map<String, dynamic>>>{};

  while (msgs.length != 3) {
    var resp = await http.get("http://localhost:8000/messages");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = (json.decode(resp.body) as List).cast();
    }
  }

  return msgs;
}

Future<Map<int, List<String>>> getErrorsFromIsolates() async {
  var msgs = <int, List<String>>{};

  while (msgs.length != 3) {
    var resp = await http.get("http://localhost:8000/errors");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = (json.decode(resp.body) as List).cast();
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
    final router = Router();
    router.route("/messages").linkFunction((req) async {
      var msgs = List.from(messages);
      messages = [];
      return Response.ok(msgs);
    });

    router.route("/errors").linkFunction((req) async {
      var msgs = List.from(errors);
      errors = [];
      return Response.ok(msgs);
    });

    router.route("/send").linkFunction((req) async {
      String msg = await req.body.decode();
      if (msg == "garbage") {
        messageHub.add((x) => x);
      } else {
        messageHub.add({"isolateID": server.identifier, "message": msg});
      }
      return Response.accepted();
    });
    return router;
  }
}
