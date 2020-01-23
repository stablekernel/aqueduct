import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Cannot bind bool to header", () {
    try {
      RuntimeContext.current;
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(),
          "Bad state: Invalid binding 'x' on 'ErrorDefaultBool.get1': Parameter type does not implement static parse method.");
    }
  });
}

class ErrorDefaultBool extends ResourceController {
  @Operation.get()
  // ignore: avoid_positional_boolean_parameters
  Future<Response> get1(@Bind.header("foo") bool x) async {
    return Response.ok(null);
  }
}
