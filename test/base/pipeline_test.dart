import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("RequestHandler requiring instantion throws exception when instantiated early", () async {
    var app = new Application<TestPipeline>();
    print("1");
    try {
      print("2");
      await app.start();
      print("3");
      expect(true, false);
    } on IsolateSupervisorException catch (e) {
      print("4");
      expect(e.message, "RequestHandler FailingController instances cannot be reused. Rewrite as .then(() => new FailingController())");
    } catch (e) {
      print("$e");
    }
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