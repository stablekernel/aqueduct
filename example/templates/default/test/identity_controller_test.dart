import 'harness/app.dart';

Future main() async {
  group("Success cases", () {
    TestApplication app = new TestApplication();

    setUp(() async {
      await app.start();

      var req = app.client.clientAuthenticatedRequest("/register")
        ..json = {
          "username": "bob@stablekernel.com",
          "password": "foobaraxegrind12%"
        };

      app.client.defaultAccessToken = (await req.post()).asMap["access_token"];
    });

    tearDown(() async {
      await app.stop();
    });

    test("Identity returns user associated with bearer token", () async {
      var req = app.client.authenticatedRequest("/me");
      var result = await req.get();

      expect(
          result,
          hasResponse(
              200,
              partial({
                "id": greaterThan(0),
                "email": "bob@stablekernel.com",
                "username": "bob@stablekernel.com"
              })));
    });
  });
}
