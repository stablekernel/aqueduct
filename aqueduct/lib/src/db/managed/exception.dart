import 'package:aqueduct/aqueduct.dart';

class ValidationException implements HandlerException {
  ValidationException(this.errors);

  final List<String> errors;

  @override
  Response get response {
    return new Response.badRequest(body: {"error": errors.join(",")});
  }

  @override
  String toString() {
    return response.body["error"];
  }
}