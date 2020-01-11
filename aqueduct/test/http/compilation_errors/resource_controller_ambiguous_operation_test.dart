import 'dart:async';
import "dart:core";

import 'package:aqueduct/aqueduct.dart';
import 'package:runtime/runtime.dart';
import "package:test/test.dart";

void main() {
  test("Ambiguous methods throws exception", () {
    try {
      RuntimeContext.current;
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("'get1'"));
      expect(e.toString(), contains("'get2'"));
      expect(e.toString(), contains("'AmbiguousController'"));
    }
  });
}

class AmbiguousController extends ResourceController {
  @Operation.get("id")
  Future<Response> get1(@Bind.path("id") int id) async {
    return Response.ok(null);
  }

  @Operation.get("id")
  Future<Response> get2(@Bind.path("id") int id) async {
    return Response.ok(null);
  }
}
