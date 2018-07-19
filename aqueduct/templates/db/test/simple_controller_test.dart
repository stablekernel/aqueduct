import 'harness/app.dart';

Future main() async {
  final harness = Harness()..install();

  tearDown(() async {
    await harness.resetData();
  });

  test("POST /model", () async {
    final response = await harness.agent.post("/model", body: {"name": "Bob"});
    expect(response, hasResponse(200, body: {"id": isNotNull, "name": "Bob", "createdAt": isTimestamp}));
  });

  test("GET /model/:id returns previously created object", () async {
    var response = await harness.agent.post("/model", body: {"name": "Bob"});

    final createdObject = response.body.as();
    response = await harness.agent.request("/model/${createdObject["id"]}").get();
    expect(
        response,
        hasResponse(200,
            body: {"id": createdObject["id"], "name": createdObject["name"], "createdAt": createdObject["createdAt"]}));
  });
}
