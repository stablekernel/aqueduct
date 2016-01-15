import 'package:monadart/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:math';

main() {
  var app = new Application<TPipeline>();
  app.configuration.port = 8080;
  app.start(numberOfInstances: 3);

}

class TPipeline extends ApplicationPipeline {
  TPipeline(Map opts) : super(opts);

  void addRoutes() {
    router.route("/t").then(new RequestHandler(requestHandler: (req) {
      req.response.statusCode = 200;
      req.response.close();
    }));
  }

  @override
  Future willOpen() async {
    if (new Random().nextInt(3) % 3 == 0) {
      print("Well");
      throw new Exception("hi");
    }
  }
}
