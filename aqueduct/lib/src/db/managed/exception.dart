import 'package:aqueduct/aqueduct.dart';

class ValidationException implements HandlerException {
  ValidationException(this.errors);

  final List<String> errors;

  @override
  Response get response {
    return Response.badRequest(
        body: {"error": "entity validation failed", "reasons": errors});
  }

  @override
  String toString() {
    final errorString = response.body["error"] as String;
    final reasons = (response.body["reasons"] as List).join(", ");
    return "$errorString $reasons";
  }
}
