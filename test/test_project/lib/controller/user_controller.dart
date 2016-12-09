import '../wildfire.dart';

class UserController extends QueryController<User> {
  UserController(this.authServer);

  AuthServer authServer;

  @httpGet
  Future<Response> getUser(@HTTPPath("id") int id) async {
    var u = await query.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    if (request.authorization.resourceOwnerIdentifier != id) {
      // Filter out stuff for non-owner of user
    }

    return new Response.ok(u);
  }

  @httpPut
  Future<Response> updateUser(@HTTPPath("id") int id) async {
    if (request.authorization.resourceOwnerIdentifier != id) {
      return new Response.unauthorized();
    }

    var u = await query.updateOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }

  @httpDelete
  Future<Response> deleteUser(@HTTPPath("id") int id) async {
    if (request.authorization.resourceOwnerIdentifier != id) {
      return new Response.unauthorized();
    }

    await authServer.revokeAuthenticatableAccessForIdentifier(id);
    var q = new Query<User>()
      ..matchOn.id = id;
    await q.delete();

    return new Response.ok(null);
  }
}
