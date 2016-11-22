import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

main() {
  test("APIResponse empty schema", () {
    var response = new APIResponse()..statusCode = 200;
    expect(response.asMap()["schema"], isNull);
  });
}
