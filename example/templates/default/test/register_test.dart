import 'harness/app.dart';

main() {
  group("Success cases", () {
    TestApplication app = new TestApplication();

    setUp(() async {
      await app.start();
    });

    tearDown(() async {
      await app.stop();
    });

    test("Can create user", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "username": "bob@stablekernel.com",
              "password": "foobaraxegrind12%"
            })
          .post();

      expect(
          response,
          hasResponse(
              200, partial({"access_token": hasLength(greaterThan(0))})));
    });

    test("Created user has same email a username", () async {
      var json = {
        "username": "bob@stablekernel.com",
        "password": "foobaraxegrind12%"
      };

      var registerResponse = await (app.client
              .clientAuthenticatedRequest("/register")..json = json)
          .post();

      var identityResponse = await (app.client.authenticatedRequest("/me",
              accessToken: registerResponse.asMap["access_token"]))
          .get();

      expect(identityResponse,
          hasResponse(200, partial({"email": json["username"]})));
    });
  });

  group("Failure cases", () {
    TestApplication app = new TestApplication();

    setUp(() async {
      await app.start();
    });

    tearDown(() async {
      await app.stop();
    });

    test("Trying to create existing user fails", () async {
      await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "username": "bob@stablekernel.com",
              "password": "someotherpassword"
            })
          .post();

      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "username": "bob@stablekernel.com",
              "password": "foobaraxegrind12%"
            })
          .post();

      expect(response, hasStatus(409));
    });

    test("Omit password fails", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "username": "bobby.bones@stablekernel.com",
            })
          .post();

      expect(response, hasStatus(400));
    });

    test("Omit username fails", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {"username": "foobaraxegrind12%"})
          .post();

      expect(response, hasStatus(400));
    });
  });
}
