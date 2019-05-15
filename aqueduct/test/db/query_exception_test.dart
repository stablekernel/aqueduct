import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Conflict returns 409", () {
    final exception = QueryException.conflict("invalid", ["xyz"]);
    expect(exception.response.statusCode, 409);
    expect(exception.response.body,
        {"error": "invalid", "detail": "Offending Items: xyz"});
  });

  test("Input returns 400", () {
    final exception = QueryException.input("invalid", ["xyz"]);
    expect(exception.response.statusCode, 400);
    expect(exception.response.body,
        {"error": "invalid", "detail": "Offending Items: xyz"});
  });

  test("Transport returns 503", () {
    final exception = QueryException.transport("invalid");
    expect(exception.response.statusCode, 503);
    expect(exception.response.body, {"error": "invalid"});
  });

  test("Offending items show in response detail", () {
    final exception = QueryException.input("invalid", ["xyz"]);
    expect(exception.response.body["detail"], contains("xyz"));
  });

  test("No detail is provided when there are no offending items", () {
    final exception = QueryException.input("invalid", []);
    expect(exception.response.body, {"error": "invalid"});
  });
}
