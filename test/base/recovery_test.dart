import 'dart:io';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

main() {
  group("Recovers", () {
    var app = new Application<TestSink>();
    HttpClient client;
    setUp(() async {
      client = new HttpClient();
    });

    tearDown(() async {
      await client.close(force: true);
      await app?.stop();
    });

    test("Application reports uncaught error, recovers", () async {
      await app.start(numberOfInstances: 1);

      // This request will generate an uncaught exception
      var failFuture = getStatusCode(client, "/");

      // This request will come in right after the failure but should succeed
      var successFuture = getStatusCode(client, "/1");

      // Ensure both requests respond with 200, since the failure occurs asynchronously AFTER the response has been generated
      // for the failure case.
      var successResponse = await successFuture;
      var failResponse = await failFuture;
      expect(successResponse, 200);
      expect(failResponse, 200);

      var errorMessage = await app.logger.onRecord.first;
      expect(errorMessage.message, contains("Uncaught exception"));
      expect(errorMessage.error.toString(), contains("foo"));
      expect(errorMessage.stackTrace, isNotNull);

      // And then we should make sure everything is working just fine.
      expect(await getStatusCode(client, "/1"), 200);
    });

    test("Application with multiple isolates reports uncaught error, recovers",
        () async {
      var contents = <String>[];
      int counter = 0;
      var completer = new Completer();
      app.logger.onRecord.listen((rec) {
        contents.add(rec.message);
        counter ++;
        if (counter == 5) {
          completer.complete();
        }
      });

      await app.start(numberOfInstances: 2);

      // Throw some deferred crashers then some success messages at the server
      var failFutures = new Iterable.generate(5)
          .map((_) => http.get("http://localhost:8081"));

      var successResponse = await http.get("http://localhost:8081/1");
      expect(successResponse.statusCode, 200);
      expect((await Future.wait(failFutures)).map((r) => r.statusCode),
          everyElement(200));

      await completer.future;
      expect(contents.where((c) => c.contains("Uncaught exception")).length, 5);
    });
  });
}

Future<int> getStatusCode(HttpClient client, String path) async {
  var req = await client.getUrl(Uri.parse("http://localhost:8081$path"));
  var resp = await req.close();

  return resp.statusCode;
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
