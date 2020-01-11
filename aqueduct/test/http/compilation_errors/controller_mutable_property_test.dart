import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:runtime/runtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    "A controller that is not Recyclable, but declares non-final properties throws a runtime error",
      () {
      try {
        RuntimeContext.current;
        fail('unreachable');
      } on StateError catch (e) {
        expect(e.toString(), contains("MutablePropertyController"));
      }
    });
}

class MutablePropertyController extends Controller {
  String mutableProperty;

  @override
  FutureOr<RequestOrResponse> handle(Request request) {
    return request;
  }
}
