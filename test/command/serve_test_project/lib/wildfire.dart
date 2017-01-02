import 'package:aqueduct/aqueduct.dart';

class WildfireSink extends RequestSink {
  WildfireSink(ApplicationConfiguration config) : super(config);

  @override
  void setupRouter(Router r) {
    r.route("/endpoint").listen((req) async => new Response.ok(null));
  }
}