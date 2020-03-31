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
        contains("NotSerializableController"));
    }
  });
}

class NotSerializableController extends ResourceController {
  @Operation.post()
  Future<Response> create(@Bind.body() Uri uri) async {
    return Response.ok(null);
  }
}