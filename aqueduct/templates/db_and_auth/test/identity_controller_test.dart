import 'package:wildfire/model/user.dart';

import 'harness/app.dart';

Future main() async {
  final harness = Harness()..install();

  Agent userClient;
  User defaultUser;

  setUp(() async {
    defaultUser = User()
      ..username = "bob@stablekernel.com"
      ..password = "foobaraxegrind12%";
    userClient = await harness.registerUser(defaultUser);
  });

  // After each test, reset the database to remove any rows it inserted.
  tearDown(() async {
    await harness.resetData();
  });

  test("Identity returns user associated with bearer token", () async {
    expectResponse(await userClient.get("/me"), 200, body: {
      "id": greaterThan(0),
      "username": defaultUser.username
    });
  });
}
