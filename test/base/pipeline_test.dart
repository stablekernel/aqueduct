import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test(
      "RequestController requiring instantion throws exception when instantiated early",
      () async {
    var app = new Application<TestSink>();
    try {
      await app.start();
      expect(true, false);
    } on ApplicationStartupException catch (e) {
      expect(
          e.toString(),
          contains(
              "RequestController subclass FailingController instances cannot be reused. Rewrite as .generate(() => new FailingController())"));
    }
  });
}

class TestSink extends RequestSink {
  TestSink(ApplicationConfiguration opts) : super(opts);

  @override
  void setupRouter(Router router) {
    router.route("/controller/[:id]").pipe(new FailingController());
  }
}

class FailingController extends HTTPController {
  @httpGet
  get() async {
    return new Response.ok(null);
  }
}
