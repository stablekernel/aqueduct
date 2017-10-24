import 'harness/app.dart';
import 'dart:convert';

Future main() async {
  TestApplication app = new TestApplication();
  List<String> tokens;

  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });

  setUp(() async {
    tokens = [];
    for (var i = 0; i < 6; i++) {
      var response = await (app.client.clientAuthenticatedRequest("/register")
        ..json = {
          "username": "bob+$i@stablekernel.com",
          "password": "foobaraxegrind$i%"
        }).post();
      tokens.add(JSON.decode(response.body)["access_token"]);
    }
  });

  tearDown(() async {
    await app.discardPersistentData();
  });

  group("Success cases", () {
    test("Can get user with valid credentials", () async {
      var response = await (app.client
          .authenticatedRequest("/users/1", accessToken: tokens[0])
          .get());

      expect(response,
          hasResponse(200, partial({"username": "bob+0@stablekernel.com"})));
    });
  });

  group("Failure cases", () {
    test("Updating user fails if not owner", () async {
      var response = await (app.client.authenticatedRequest("/users/1",
              accessToken: tokens[4])..json = {"email": "a@a.com"})
          .put();

      expect(response, hasStatus(401));
    });
  });
}
