import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
  group("Recovers", () {
    var app = new Application<TestSink>();

    tearDown(() async {
      await app?.stop();
    });

    test("Application reports uncaught error, recovers", () async {
      await app.start(numberOfInstances: 1);

      // This request will generate an uncaught exception
      var failFuture = http.get("http://localhost:8080/");

      // This request will come in right after the failure but should succeed
      var successFuture = http.get("http://localhost:8080/1");

      // Ensure both requests respond with 200, since the failure occurs asynchronously AFTER the response has been generated
      // for the failure case.
      var successResponse = await successFuture;
      var failResponse = await failFuture;
      expect(successResponse.statusCode, 200);
      expect(failResponse.statusCode, 200);

      var errorMessage = await app.logger.onRecord.first;
      expect(errorMessage.message, contains("Uncaught exception"));
      expect(errorMessage.error.toString(), contains("foo"));
      expect(errorMessage.stackTrace, isNotNull);

      // And then we should make sure everything is working just fine.
      expect((await http.get("http://localhost:8080/1")).statusCode, 200);
    });

    test("Application with multiple isolates reports uncaught error, recovers",
        () async {
      await app.start(numberOfInstances: 2);

      // Throw some deferred crashers then some success messages at the server
      var failFutures = new Iterable.generate(5)
          .map((_) => http.get("http://localhost:8080"));
      var successResponse = await http.get("http://localhost:8080/1");
      expect(successResponse.statusCode, 200);

      var logMessages = await app.logger.onRecord.take(5);
      logMessages.forEach((errorMessage) {
        expect(errorMessage.message, contains("Uncaught exception"));
        expect(errorMessage.error.toString(), contains("foo"));
        expect(errorMessage.stackTrace, isNotNull);
      });

      expect((await Future.wait(failFutures)).map((r) => r.statusCode),
          everyElement(200));
    });
  });
}

class TestSink extends RequestSink {
  TestSink(dynamic any) : super(null);

  @override
  void setupRouter(Router router) {
    router.route("/[:id]").generate(() => new UncaughtCrashController());
  }
}

class UncaughtCrashController extends HTTPController {
  @httpGet
  crashUncaught() async {
    new Future(() {
      var x = null;
      x.foo();
    });
    return new Response.ok(null);
  }

  @httpGet
  dontCrash(@HTTPPath("id") int id) async {
    return new Response.ok(null);
  }
}
