import 'dart:async';

import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  group("Default harness", () {
    TestHarness<Channel> harness;

    setUp(() {
      harness = TestHarness<Channel>();
    });

    tearDown(() async {
      await harness?.stop();
    });

    test("options are used by application", () async {
      harness.options.context["key"] = "value";
      await harness.start();

      // default value
      expect(harness.channel.options.configurationFilePath, "config.src.yaml");

      // provided value
      expect(harness.channel.options.context, {"key": "value"});
    });

    test(
        "Can start app in test mode and make a request to it with defaultClient",
        () async {
      await harness.start();
      expectResponse(await harness.agent.request("endpoint").get(), 200,
          body: {"key": "value"});
      expect(harness.application.isRunning, true);
    });

    test("Can stop and restart an application", () async {
      await harness.start();
      expectResponse(await harness.agent.request("endpoint").get(), 200,
          body: {"key": "value"});
      expect(harness.application.isRunning, true);
      await harness.stop();
      expect(harness.application, isNull);
      await harness.start();
      expectResponse(await harness.agent.request("endpoint").get(), 200,
          body: {"key": "value"});
      expect(harness.application.isRunning, true);
    });
  });

  group("Harness subclasses", () {
    final harness = HarnessSubclass()..install();

    test("beforeStart runs prior to running app", () {
      expect(harness.events.first.first, 'beforeStart');
      expect(harness.events.first.last, false);
      expect(harness.setupCount, 1);
      expect(harness.tearDownCount, 0);
    });

    test("afterStart runs after running app", () {
      expect(harness.events.last.first, 'afterStart');
      expect(harness.events.last.last, true);
      expect(harness.setupCount, 2);
      expect(harness.tearDownCount, 1);

    });

    test("agent is set prior to afterStart running", () async {
      expect(harness.isAgentCreatedInAfterStart, true);
    });
  });
}

class Channel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/endpoint")
        .linkFunction((req) async => Response.ok({"key": "value"}));
    return router;
  }
}

class HarnessSubclass extends TestHarness<Channel> {
  int setupCount = 0;
  int tearDownCount = 0;

  List<List<dynamic>> events = [];
  bool isAgentCreatedInAfterStart = false;

  @override
  Future beforeStart() async {
    events.add(["beforeStart", application.isRunning]);
  }

  @override
  Future afterStart() async {
    isAgentCreatedInAfterStart = agent != null;
    events.add(["afterStart", application.isRunning]);
  }

  @override
  Future onSetUp() async {
    setupCount ++;
  }

  @override
  Future onTearDown() async {
    tearDownCount ++;
  }


}
