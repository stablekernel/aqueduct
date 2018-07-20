import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Conflict returns 409", () {
    final exception = QueryException.conflict("invalid", ["xyz"]);
    expect(exception.response.statusCode, 409);
    expect(exception.response.body, {"error": "invalid"});
  });

  test("Input returns 400", () {
    final exception = QueryException.input("invalid", ["xyz"]);
    expect(exception.response.statusCode, 400);
    expect(exception.response.body, {"error": "invalid"});
  });

  test("Transport returns 503", () {
    final exception = QueryException.transport("invalid");
    expect(exception.response.statusCode, 503);
    expect(exception.response.body, {"error": "invalid"});
  });
}
