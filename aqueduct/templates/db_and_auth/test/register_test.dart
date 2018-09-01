import 'harness/app.dart';

void main() {
  final harness = Harness()..install();

  tearDown(() async {
    await harness.resetData();
  });

  test("Can create user", () async {
    final response = await harness.publicAgent.post("/register", body: {
      "username": "bob@stablekernel.com",
      "password": "foobaraxegrind12%"
    });

    expect(
        response,
        hasResponse(200,
            body: partial({
              "username": isString,
              "authorization":
                  partial({"access_token": hasLength(greaterThan(0))})
            })));
  });

  test("Trying to create existing user fails", () async {
    await harness.publicAgent.post("/register", body: {
      "username": "bob@stablekernel.com",
      "password": "someotherpassword"
    });

    final response = await harness.publicAgent.post("/register", body: {
      "username": "bob@stablekernel.com",
      "password": "foobaraxegrind12%"
    });
    expect(response, hasStatus(409));
  });

  test("Omit password fails", () async {
    final response = await harness.publicAgent.post("/register", body: {
      "username": "bobby.bones@stablekernel.com",
    });

    expect(response, hasStatus(400));
  });

  test("Omit username fails", () async {
    final response = await harness.publicAgent
        .post("/register", body: {"username": "foobaraxegrind12%"});

    expect(response, hasStatus(400));
  });
}
