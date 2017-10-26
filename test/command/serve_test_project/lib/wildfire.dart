import 'package:aqueduct/aqueduct.dart';

class WildfireChannel extends ApplicationChannel {
  @override
  RequestController get entryPoint {
    final r = new Router();
    r.route("/endpoint").listen((req) async => new Response.ok(null));
    return r;
  }
}
