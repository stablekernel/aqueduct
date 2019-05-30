import 'dart:async';
import "dart:core";

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/runtime/mirror_impl.dart';
import "package:test/test.dart";

void main() {
  test("Ambiguous methods throws exception", () {
    try {
      RuntimeLoader.load();
      fail('unreachable');
    } on StateError catch (e) {
      expect(e.toString(), contains("Invalid controller"));
      expect(e.toString(), contains("'UnboundController'"));
      expect(e.toString(), contains("'getOne'"));
    }
  });
}

class UnboundController extends ResourceController {
  @Operation.get()
  Future<Response> getOne(@Bind.path("id") int id) async {
    return Response.ok(null);
  }
}