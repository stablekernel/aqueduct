import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  Controller.addExceptionHandler(String, (req, String exception, {StackTrace trace}) {
    return new Response.ok(null);
  });

  print("${Controller.exceptionHandlers[String](null, "foo").statusCode}");
}