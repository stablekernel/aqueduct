import 'dart:async';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test(
      "Controller requiring instantion throws exception when instantiated early",
      () async {
    var app = new Application<TestChannel>();
    try {
      await app.start();
      expect(true, false);
    } on ApplicationStartupException catch (e) {
      expect(
          e.toString(),
          contains(
              "'FailingController' instances cannot be reused between requests. Rewrite as .generate(() => new FailingController())"));
    }
  });

  test("Find default ApplicationChannel", () {
    expect(ApplicationChannel.defaultType, equals(TestChannel));
  });
}

class TestChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router.route("/controller/[:id]").pipe(new FailingController());
    return router;
  }
}

class FailingController extends RESTController {
  @Bind.get()
  Future<Response> get() async {
    return new Response.ok(null);
  }
}
