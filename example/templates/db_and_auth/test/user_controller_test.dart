import 'harness/app.dart';
import 'dart:convert';

Future main() async {
  group("Success cases", () {
    TestApplication app = new TestApplication();
    List<String> tokens;

    setUp(() async {
      await app.start();

      tokens = [];
      for (var i = 0; i < 6; i++) {
        var response = await (app.client.clientAuthenticatedRequest("/register")
              ..json = {
                "username": "bob+$i@stablekernel.com",
                "password": "foobaraxegrind$i%"
              })
            .post();
        tokens.add(JSON.decode(response.body)["access_token"]);
      }
    });

    tearDown(() async {
      await app.stop();
    });

    test("Can get user with valid credentials", () async {
      var response = await (app.client
          .authenticatedRequest("/users/1", accessToken: tokens[0])
          .get());

      expect(response,
          hasResponse(200, partial({"username": "bob+0@stablekernel.com"})));
    });
  });

  group("Failure cases", () {
    TestApplication app = new TestApplication();
    var tokens;

    setUp(() async {
      await app.start();

      var responses = await Future.wait([0, 1, 2, 3, 4, 5].map((i) {
        return (app.client.clientAuthenticatedRequest("/register")
              ..json = {
                "username": "bob+$i@stablekernel.com",
                "password": "foobaraxegrind$i%"
              })
            .post();
      }));

      tokens = responses
          .map((resp) => JSON.decode(resp.body)["access_token"])
          .toList();
    });

    tearDown(() async {
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
