import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Default harness", () {
    TestHarness<Channel> harness;

    setUp(() {
      harness = new TestHarness<Channel>();
    });

    tearDown(() async {
      await harness?.tearDown();
    });

    test("options are used by application", () async {
      harness.options.context["key"] = "value";
      await harness.setUp();

      // default value
      expect(harness.channel.options.configurationFilePath, "config.src.yaml");

      // provided value
      expect(harness.channel.options.context, {"key": "value"});
    });

    test("Can start app in test mode and make a request to it with defaultClient", () async {
      await harness.setUp();
      expectResponse(await harness.agent.request("endpoint").get(), 200, body: {"key": "value"});
      expect(harness.application.isRunning, true);
    });

    test("Can stop and restart an application", () async {
      await harness.setUp();
      expectResponse(await harness.agent.request("endpoint").get(), 200, body: {"key": "value"});
      expect(harness.application.isRunning, true);
      await harness.tearDown();
      expect(harness.application, isNull);
      await harness.setUp();
      expectResponse(await harness.agent.request("endpoint").get(), 200, body: {"key": "value"});
      expect(harness.application.isRunning, true);
    });
  });

  group("Harness subclasses", () {
    HarnessSubclass harness;

    setUp(() async {
      harness = new HarnessSubclass();
      await harness.setUp();
    });

    tearDown(() async {
      await harness?.tearDown();
    });

    test("beforeStart runs prior to running app", () {
      expect(harness.events.first.first, 'beforeStart');
      expect(harness.events.first.last, false);
    });

    test("afterStart runs after running app", () {
      expect(harness.events.last.first, 'afterStart');
      expect(harness.events.last.last, true);
    });

    test("agent is set prior to afterStart running", () async {
      expect(harness.isAgentCreatedInAfterStart, true);
    });
  });
}

class Channel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/endpoint").linkFunction((req) async => new Response.ok({"key": "value"}));
    return router;
  }
}

class HarnessSubclass extends TestHarness<Channel> {
  List<List<dynamic>> events = [];
  bool isAgentCreatedInAfterStart = false;

  Future beforeStart() async {
    events.add(["beforeStart", application.isRunning]);
  }

  Future afterStart() async {
    isAgentCreatedInAfterStart = agent != null;
    events.add(["afterStart", application.isRunning]);
  }
}