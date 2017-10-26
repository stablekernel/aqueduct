import 'package:aqueduct/aqueduct.dart';

class WildfireSink extends RequestSink {
  @override
  RequestController get entry {
    final r = new Router();
    r.route("/endpoint").listen((req) async => new Response.ok(null));
    return r;
  }
}
