import 'package:wildfire/model/user.dart';

import 'harness/app.dart';

Future main() async {
  Harness harness = new Harness()..install();

  Agent userClient;

  final defaultUser = new User()
    ..username = "bob@stablekernel.com"
    ..password = "foobaraxegrind12%";

  setUp(() async {
    userClient = await harness.registerUser(defaultUser);
  });

  // After each test, reset the database to remove any rows it inserted.
  tearDown(() async {
    await harness.resetData();
  });

  test("Identity returns user associated with bearer token", () async {
    expectResponse(await userClient.get("/me"), 200, body: {
      "id": greaterThan(0),
      "email": defaultUser.username,
      "username": defaultUser.username
    });
  });
}
