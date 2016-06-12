import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:mirrors';

void main() {
  test("RequestHandler requiring instantion throws exception when instantiated early", () async {
    var app = new Application<TestPipeline>();
    var success = false;
    try {
      await app.start();
      success = true;
    } on IsolateSupervisorException catch (e) {
      expect(e.message, "RequestHandler FailingController instances cannot be reused. Rewrite as .then(() => new FailingController())");
    }
    expect(success, false);
  });
}

class TestPipeline extends ApplicationPipeline {
  TestPipeline(dynamic opts) : super (opts);

  @override
  void addRoutes() {
    router
        .route("/controller/[:id]")
        .then(new FailingController());
  }
}
class FailingController extends HttpController {
  @httpGet get() async {
    return new Response.ok(null);
  }
}