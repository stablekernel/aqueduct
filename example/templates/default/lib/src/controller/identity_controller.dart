part of wildfire;

class IdentityController extends HTTPController {
  @httpGet getIdentity() async {
    var q = new Query<User>()
      ..id = request.permission.resourceOwnerIdentifier;
    
    var u = await q.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }
}
