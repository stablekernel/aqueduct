import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    "A controller that is not Recyclable, but declares a setter throws a runtime error",
      () {
      try {
        Runtime.current;
        fail('unreachable');
      } on StateError catch (e) {
        expect(e.toString(), contains("MutableSetterController"));
      }
    });
}

class MutableSetterController extends Controller {
  set mutableSetter(String s) {}

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}
