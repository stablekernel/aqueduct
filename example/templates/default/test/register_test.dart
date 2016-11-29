import 'harness/app.dart';

main() {
  group("Success cases", () {
    TestApplication app = new TestApplication();

    setUpAll(() async {
      await app.start();
    });

    tearDownAll(() async {
      await app.stop();
    });

    test("Can create user", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "email": "bob@stablekernel.com",
              "password": "foobaraxegrind12%"
            })
          .post();

      expect(
          response,
          hasResponse(
              200, partial({"access_token": hasLength(greaterThan(0))})));
    });
  });

  group("Failure cases", () {
    TestApplication app = new TestApplication();

    setUpAll(() async {
      await app.start();
    });

    tearDownAll(() async {
      await app.stop();
    });
    test("Trying to create existing user fails", () async {
      await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "email": "bob@stablekernel.com",
              "password": "someotherpassword"
            })
          .post();

      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "email": "bob@stablekernel.com",
              "password": "foobaraxegrind12%"
            })
          .post();

      expect(response, hasStatus(409));
    });

    test("Omit password fails", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {
              "email": "bobby.bones@stablekernel.com",
            })
          .post();

      expect(response, hasStatus(400));
    });

    test("Omit username fails", () async {
      var response = await (app.client.clientAuthenticatedRequest("/register")
            ..json = {"password": "foobaraxegrind12%"})
          .post();

      expect(response, hasStatus(400));
    });
  });
}
