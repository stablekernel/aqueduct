import 'package:aqueduct/aqueduct.dart';

class ValidationException implements HandlerException {
  ValidationException(this.errors);

  final List<String> errors;

  @override
  RequestOrResponse get requestOrResponse {
    return new Response.badRequest(body: {"error": errors.join(",")});
  }

  @override
  String toString() {
    return (requestOrResponse as Response).body["error"];
  }
}