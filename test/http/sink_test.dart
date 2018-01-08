import 'dart:async';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("Find default ApplicationChannel", () {
    expect(ApplicationChannel.defaultType, equals(TestChannel));
  });
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/controller/[:id]").link(() =>new FailingController());
    return router;
  }
}

class FailingController extends RESTController {
  @Operation.get()
  Future<Response> get() async {
    return new Response.ok(null);
  }
}
