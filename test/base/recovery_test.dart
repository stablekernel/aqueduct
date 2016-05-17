import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

main() {
//  group("Recovers", () {
//    var app = new Application<Pipeline>();
//
//    tearDownAll(() async {
//      await app?.stop();
//    });
//
//    test("Application reports uncaught error, recovers", () async {
//      List<LogRecord> logQueue = [];
//      app.logger.onRecord.listen((rec) => logQueue.add(rec));
//      await app.start(numberOfInstances: 1);
//      await http.get("http://localhost:8080/");
//
//      // This request should timeout and fail.
//      var timeoutRan = false;
//      await http.get("http://localhost:8080/1").timeout(new Duration(milliseconds: 500), onTimeout: () {
//        timeoutRan = true;
//      });
//      expect(timeoutRan, true);
//
//      await new Future.delayed(new Duration(seconds: 3));
//
//      // After restart, this should succeeded.
//      var response = await http.get("http://localhost:8080/1");
//      expect(response.statusCode, 200);
//
//      expect(logQueue.length, 1);
//      expect(logQueue.first.message, startsWith("Restarting terminated isolate. Exit reason"));
//
//      await app.stop();
//    });
//
//    test("Application with multiple isolates where one dies recovers", () async {
//      List<LogRecord> logQueue = [];
//      app.logger.onRecord.listen((rec) => logQueue.add(rec));
//      await app.start(numberOfInstances: 2);
//      await http.get("http://localhost:8080/");
//
//      // This request should succeed, the other isolate will pick it up.
//      var response = await http.get("http://localhost:8080/1");
//      expect(response.statusCode, 200);
//
//      expect(logQueue.length, 1);
//      expect(logQueue.first.message, startsWith("Restarting terminated isolate. Exit reason"));
//
//      // Wait for new isolate to pick back up...
//      await new Future.delayed(new Duration(seconds: 3));
//
//      var startTime = new DateTime.now();
//
//      bool foundFirstServer = false;
//      bool foundSecondServer = false;
//      while (!foundFirstServer && !foundSecondServer) {
//        response = await http.get("http://localhost:8080/1");
//        expect(response.statusCode, 200);
//
//        var serverIdentifier = response.headers["server"].split("/").last;
//        if (serverIdentifier == "1") {
//          foundFirstServer = true;
//        } else if (serverIdentifier == "2") {
//          foundSecondServer = true;
//        }
//
//        if (new DateTime.now().difference(startTime).abs().inSeconds > 20) {
//          fail("Could not get response.");
//        }
//      }
//
//      await app.stop();
//    });
//
//    test("", () {});
//  });
}

class Pipeline extends ApplicationPipeline {
  Pipeline(dynamic any) : super(null);

  @override
  void addRoutes() {
    router.route("/[:id]").then(new RequestHandlerGenerator<UncaughtCrashController>());
  }
}

class UncaughtCrashController extends HttpController {
  @httpGet crashUncaught() async {
    new Future(() {
      var x = null;
      x.foo();
      print("HELLO");
    }).then((_) {

    });
    return new Response.ok(null);
  }

  @httpGet dontCrash(int id) async {
    return new Response.ok(null);
  }
}