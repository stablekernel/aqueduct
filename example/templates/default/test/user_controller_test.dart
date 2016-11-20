import 'dart:async';

import 'package:test/test.dart';
import 'package:wildfire/wildfire.dart';
import 'dart:convert';
import 'mock/startup.dart';

Future main() async {
  group("Success cases", () {
    TestApplication app = new TestApplication();
    var tokens;

    setUpAll(() async {
      await app.start();

      var responses = await Future.wait([0, 1, 2, 3, 4, 5].map((i) {
        return (app.client.clientAuthenticatedRequest("/register")
              ..json = {
                "email": "bob+$i@stablekernel.com",
                "password": "foobaraxegrind$i%"
              })
            .post();
      }));

      tokens = responses
          .map((resp) => JSON.decode(resp.body)["access_token"])
          .toList();
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Can get user with valid credentials", () async {
      var response = await (app.client
          .authenticatedRequest("/users/1", accessToken: tokens[0])
          .get());

      expect(response,
          hasResponse(200, partial({"email": "bob+0@stablekernel.com"})));
    });

    test("Updating user can update email", () async {
      var response = await (app.client.authenticatedRequest("/users/1",
              accessToken: tokens[0])..json = {"email": "a@a.com"})
          .put();

      expect(
          response, hasResponse(200, partial({"email": "a@a.com", "id": 1})));
    });
  });

  group("Failure cases", () {
    TestApplication app = new TestApplication();
    var tokens;

    setUpAll(() async {
      await app.start();

      var responses = await Future.wait([0, 1, 2, 3, 4, 5].map((i) {
        return (app.client.clientAuthenticatedRequest("/register")
              ..json = {
                "email": "bob+$i@stablekernel.com",
                "password": "foobaraxegrind$i%"
              })
            .post();
      }));

      tokens = responses
          .map((resp) => JSON.decode(resp.body)["access_token"])
          .toList();
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Updating user fails if not owner", () async {
      var response = await (app.client.authenticatedRequest("/users/1",
              accessToken: tokens[4])..json = {"email": "a@a.com"})
          .put();

      expect(response, hasStatus(401));
    });
  });
}
