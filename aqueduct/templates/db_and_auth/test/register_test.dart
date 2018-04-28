import 'harness/app.dart';

void main() {
  TestApplication app = new TestApplication();

  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });

  tearDown(() async {
    await app.discardPersistentData();
  });

  group("Success cases", () {
    test("Can create user", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {"username": "bob@stablekernel.com", "password": "foobaraxegrind12%"})
          .post();

      expect(response, hasResponse(200, body: partial({"access_token": hasLength(greaterThan(0))})));
    });

    test("Can create user with public client", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register", clientID: "com.aqueduct.public")
            ..json = {"username": "bob@stablekernel.com", "password": "foobaraxegrind12%"})
          .post();

      expect(response, hasResponse(200, body: partial({"access_token": hasLength(greaterThan(0))})));
    });

    test("Created user has same email a username", () async {
      var json = {"username": "bob@stablekernel.com", "password": "foobaraxegrind12%"};

      var registerResponse = await (app.client.clientAuthenticatedRequest("/register")..json = json).post();

      var identityResponse =
          await (app.client.authenticatedRequest("/me", accessToken: registerResponse.asMap["access_token"])).get();

      expect(identityResponse, hasResponse(200, body: partial({"email": json["username"]})));
    });
  });

  group("Failure cases", () {
    test("Trying to create existing user fails", () async {
      await (app.client.clientAuthenticatedRequest("/register")
            ..json = {"username": "bob@stablekernel.com", "password": "someotherpassword"})
          .post();

      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {"username": "bob@stablekernel.com", "password": "foobaraxegrind12%"})
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
      var response =
          await (app.client.clientAuthenticatedRequest("/register")..json = {"username": "foobaraxegrind12%"}).post();

      expect(response, hasStatus(400));
    });
  });
}
