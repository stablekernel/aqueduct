import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("RequestHandler requiring instantion throws exception when instantiated early", () async {
    var app = new Application<TestPipeline>();
    try {
      await app.start();
      expect(true, false);
    } on IsolateSupervisorException catch (e) {
      expect(e.message, "RequestHandler FailingController instances cannot be reused. Rewrite as .thenGenerate(() => new FailingController())");
    }
  });
}

class TestPipeline extends ApplicationPipeline {
  TestPipeline(Map<String, dynamic> opts) : super (opts);

  @override
  void addRoutes() {
    router
        .route("/controller/[:id]")
        .thenDeliver(new FailingController());
  }
}
class FailingController extends HTTPController {
  @httpGet get() async {
    return new Response.ok(null);
  }
}