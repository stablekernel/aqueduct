import 'harness/app.dart';

Future main() async {
  TestApplication app = new TestApplication();

  setUpAll(() async {
    await app.start();
    var req = app.client.clientAuthenticatedRequest("/register")
      ..json = {
        "username": "bob@stablekernel.com",
        "password": "foobaraxegrind12%"
      };

    app.client.defaultAccessToken = (await req.post()).asMap["access_token"];
  });

  tearDownAll(() async {
    await app.stop();
  });

  tearDown(() async {
    await app.discardPersistentData();
  });

  group("Success cases", () {
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
