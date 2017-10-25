import 'harness/app.dart';

Future main() async {
  TestApplication app = new TestApplication();

  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });

  group("Success flow", () {
    test("Can hit example endpoint", () async {
      var request = app.client.request("/example");

      var response = await request.get();
      expect(response, hasResponse(200, {
        "key": "value"
      }));
    });
  });
}
