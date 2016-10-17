part of wildfire;

class UserController extends QueryController<User> {
  @httpGet getUser(int id) async {
    var u = await query.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    if (request.permission.resourceOwnerIdentifier != id) {
      // Filter out stuff for non-owner of user
    }

    return new Response.ok(u);
  }

  @httpPut updateUser(int id) async {
    if (request.permission.resourceOwnerIdentifier != id) {
      return new Response.unauthorized();
    }

    var u = await query.updateOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }
}
