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
      app = new Application<HubChannel>()..configuration.port = 8000;
      await app.start(numberOfInstances: numberOfIsolates);

      var resp = await postMessage("msg1");
      var receivingID = isolateIdentifierFromResponse(resp);
      var messages = await getMessagesFromIsolates();

      var id1 = 1;
      var id2 = 2;
      if (receivingID == 1) {
        id1 = 3;
      } else if (receivingID == 2) {
        id2 = 3;
      }
      expect(messages[receivingID], []);
      expect(messages[id1], [{"isolateID": receivingID, "message": "msg1"}]);
      expect(messages[id2], [{"isolateID": receivingID, "message": "msg1"}]);
    });

    test("A message sent in prepare is received by all channels eventually", () async {
      app = new Application<HubChannel>()
        ..configuration.port = 8000
        ..configuration.options = {"sendIn": "prepare"};
      await app.start(numberOfInstances: numberOfIsolates);

      var messages = await getMessagesFromIsolates();

      expect(messages[1].length, 2);
      expect(messages[1].any((i) => i["isolateID"] == 2 && i["message"] == "init"), true);
      expect(messages[1].any((i) => i["isolateID"] == 3 && i["message"] == "init"), true);

      expect(messages[2].length, 2);
      expect(messages[2].any((i) => i["isolateID"] == 1 && i["message"] == "init"), true);
      expect(messages[2].any((i) => i["isolateID"] == 3 && i["message"] == "init"), true);

      expect(messages[3].length, 2);
      expect(messages[3].any((i) => i["isolateID"] == 1 && i["message"] == "init"), true);
      expect(messages[3].any((i) => i["isolateID"] == 2 && i["message"] == "init"), true);
    });
  });

  group("Multiple listeners", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Message hub stream can have multiple listeners", () async {
      app = new Application<HubChannel>()
        ..configuration.port = 8000
        ..configuration.options = {"multipleListeners": true};
      await app.start(numberOfInstances: numberOfIsolates);

      var resp = await postMessage("msg1");
      var receivingID = isolateIdentifierFromResponse(resp);
      var messages = await getMessagesFromIsolates();

      var id1 = 1;
      var id2 = 2;
      if (receivingID == 1) {
        id1 = 3;
      } else if (receivingID == 2) {
        id2 = 3;
      }
      expect(messages[receivingID], []);
      expect(messages[id1], [{"isolateID": receivingID, "message": "msg1"}, {"isolateID": receivingID, "message": "msg1"}]);
      expect(messages[id2], [{"isolateID": receivingID, "message": "msg1"}, {"isolateID": receivingID, "message": "msg1"}]);
    });

  });

  group("Failure cases", () {
    Application app;

    tearDown(() async {
      await app?.stop();
    });

    test("Send invalid x-isolate data returns error in error stream", () async {
      app = new Application<HubChannel>()
        ..configuration.port = 8000;
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

      var messages = await getMessagesFromIsolates();
      messages.forEach((isolateID, messages) {
        if (isolateID != serverID) {
          expect(messages.any((m) => m["isolateID"] == serverID && m["message"] == "ok"), true);
        }
      });
    });
  });
}

Future<http.Response> postMessage(String message) async {
  return http.post("http://localhost:8000/send",
      headers: {HttpHeaders.CONTENT_TYPE: ContentType.TEXT.toString()},
      body: message);
}


Future<Map<int, List<Map<String, dynamic>>>> getMessagesFromIsolates() async {
  var msgs = {};

  while (msgs.length != numberOfIsolates) {
    var resp = await http.get("http://localhost:8000/messages");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = JSON.decode(resp.body);
    }
  }

  return msgs;
}

Future<Map<int, List<String>>> getErrorsFromIsolates() async {
  var msgs = {};

  while (msgs.length != numberOfIsolates) {
    var resp = await http.get("http://localhost:8000/errors");
    var serverID = isolateIdentifierFromResponse(resp);

    if (!msgs.containsKey(serverID)) {
      msgs[serverID] = JSON.decode(resp.body);
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
      messages.add(event);
    }, onError: (err) {
      errors.add(err.toString());
    });

    if (configuration.options["multipleListeners"] == true) {
      messageHub.listen((event) {
        messages.add(event);
      }, onError: (err) {
        errors.add(err.toString());
      });
    }

    if (configuration.options["sendIn"] == "prepare") {
      messageHub.add({"isolateID": server.identifier, "message": "init"});
    }
  }

  @override
  RequestController get entryPoint {
    final router = new Router();
    router.route("/messages").listen((req) async {
      var msgs = new List.from(messages);
      messages = [];
      return new Response.ok(msgs);
    });

    router.route("/errors").listen((req) async {
      var msgs = new List.from(errors);
      errors = [];
      return new Response.ok(msgs);
    });

    router.route("/send").listen((req) async {
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