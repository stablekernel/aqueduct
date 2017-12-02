import '../wildfire.dart';
import '../model/user.dart';

class IdentityController extends RESTController {
  @Bind.get()
  Future<Response> getIdentity() async {
    var q = new Query<User>()
      ..where.id = whereEqualTo(request.authorization.resourceOwnerIdentifier);

    var u = await q.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }
}
