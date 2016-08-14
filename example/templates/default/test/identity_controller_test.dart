import 'dart:async';

import 'package:test/test.dart';
import 'package:wildfire/wildfire.dart';
import 'dart:convert';
import 'mock/startup.dart';
Future main() async {
  group("1", () {
    TestApplication app = new TestApplication();

    setUpAll(() async {
      await app.start();

      var req = app.client.clientAuthenticatedRequest("/register")
        ..json = {"email": "bob@stablekernel.com", "password": "foobaraxegrind12%"};
      app.client.defaultAccessToken = (await req.post()).asMap["access_token"];
    });

    tearDownAll(() async {
      try {
        await app.stop();
      } catch (e) {
        print("$e");
      }
    });

    test("Identity returns user with valid token", () async {
      var req = app.client.authenticatedRequest("/identity");
      var result = await req.get();

      expect(result, hasResponse(200, partial({
        "id": greaterThan(0)
      })));
    });
  });
}
