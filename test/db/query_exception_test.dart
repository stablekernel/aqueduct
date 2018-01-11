import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Conflict returns 409", () {
    final exception = new QueryException.conflict("invalid", ["xyz"]);
    expect(exception.requestOrResponse is Response, true);
    expect((exception.requestOrResponse as Response).statusCode, 409);
    expect((exception.requestOrResponse as Response).body, {"error": "invalid"});
  });

  test("Input returns 400", () {
    final exception = new QueryException.input("invalid", ["xyz"]);
    expect(exception.requestOrResponse is Response, true);
    expect((exception.requestOrResponse as Response).statusCode, 400);
    expect((exception.requestOrResponse as Response).body, {"error": "invalid"});
  });

  test("Transport returns 503", () {
    final exception = new QueryException.transport("invalid");
    expect(exception.requestOrResponse is Response, true);
    expect((exception.requestOrResponse as Response).statusCode, 503);
    expect((exception.requestOrResponse as Response).body, {"error": "invalid"});
  });
}