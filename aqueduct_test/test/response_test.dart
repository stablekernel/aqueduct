import 'package:matcher/matcher.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:aqueduct_test/src/body_matcher.dart';
import 'package:aqueduct_test/src/response_matcher.dart';
import 'package:test/test.dart';

void main() {
  MockHTTPServer server;
  final agent = Agent.onPort(8000);

  setUp(() async {
    server = MockHTTPServer(8000);
    await server.open();
  });

  tearDown(() async {
    await server.close();
  });

  test("Mismatched body shows decoded body and teh reason for the mismatch",
      () async {
    server.queueHandler((req) {
      return Response.ok({"key": "value"});
    });

    final response = await agent.get("/");
    final responseMatcher = HTTPResponseMatcher(
        200, null, HTTPBodyMatcher(equals({"notkey": "bar"})));
    expect(responseMatcher.matches(response, {}), false);

    final desc = StringDescription();
    responseMatcher.describe(desc);
    expect(desc.toString(), contains("Status code must be 200"));
    expect(desc.toString(), contains("{'notkey': 'bar'}"));

    final actual = response.toString();
    expect(actual, contains("Status code is 200"));
    expect(actual, contains("{key: value}"));
  });
}
