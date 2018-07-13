import '../wildfire.dart';
import '../model/user.dart';

class IdentityController extends ResourceController {
  IdentityController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> getIdentity() async {
    var q = new Query<User>(context)
      ..where((o) => o.id).equalTo(request.authorization.ownerID);

    var u = await q.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }
}
