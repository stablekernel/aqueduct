import 'harness/app.dart';

Future main() async {
  group("Success cases", () {
    TestApplication app = new TestApplication();

    setUpAll(() async {
      await app.start();

      var req = app.client.clientAuthenticatedRequest("/register")
        ..json = {
          "email": "bob@stablekernel.com",
          "password": "foobaraxegrind12%"
        };
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

      expect(result, hasResponse(200, partial({"id": greaterThan(0)})));
    });
  });
}
