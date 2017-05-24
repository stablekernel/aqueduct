import 'harness/app.dart';

Future main() async {
  group("Success flow", () {
    TestApplication app = new TestApplication();

    setUp(() async {
      await app.start();
    });

    tearDown(() async {
      await app.stop();
    });

    test("Can create model", () async {
      var request = app.client.request("/model")
        ..json = {
          "name": "Bob"
        };

      var response = await request.post();
      expect(response, hasResponse(200, {
        "id": isNotNull,
        "name": "Bob",
        "createdAt": isTimestamp
      }));
    });

    test("Can get model", () async {
      var request = app.client.request("/model")
        ..json = {
          "name": "Bob"
        };

      var response = await request.post();
      var createdModelID = response.asMap["id"];

      response = await app.client.request("/model/$createdModelID").get();
      expect(response, hasResponse(200, {
        "id": response.asMap["id"],
        "name": response.asMap["name"],
        "createdAt": response.asMap["createdAt"]
      }));
    });
  });
}
