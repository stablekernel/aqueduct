import 'package:aqueduct/aqueduct.dart';

class WildfireChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final r = new Router();
    r.route("/endpoint").linkFunction((req) async => new Response.ok(null));
    return r;
  }
}
