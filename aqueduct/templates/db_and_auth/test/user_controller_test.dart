import 'package:wildfire/model/user.dart';

import 'harness/app.dart';

Future main() async {
  final harness = Harness()..install();

  Map<int, Agent> agents;

  setUp(() async {
    agents = {};
    for (var i = 0; i < 6; i++) {
      final user = User()
        ..username = "bob+$i@stablekernel.com"
        ..password = "foobaraxegrind$i%";
      agents[i] = await harness.registerUser(user);
    }
  });

  tearDown(() async {
    await harness.resetData();
  });

  test("Can get user with valid credentials", () async {
    final response = await agents[0].get("/users/1");
    expect(response, hasResponse(200, body: partial({"username": "bob+0@stablekernel.com"})));
  });

  test("Updating user fails if not owner", () async {
    final response = await agents[4].put("/users/1", body: {"username": "a@a.com"});
    expect(response, hasStatus(401));
  });
}
