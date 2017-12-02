import '../wildfire.dart';
import '../model/user.dart';

class UserController extends QueryController<User> {
  UserController(this.authServer);

  AuthServer authServer;

  @Operation.get("id")
  Future<Response> getUser(@Bind.path("id") int id) async {
    var u = await query.fetchOne();
    if (u == null) {
      return new Response.notFound();
    }

    if (request.authorization.resourceOwnerIdentifier != id) {
      // Filter out stuff for non-owner of user
    }

    return new Response.ok(u);
  }

  @Operation.put("id")
  Future<Response> updateUser(@Bind.path("id") int id) async {
    if (request.authorization.resourceOwnerIdentifier != id) {
      return new Response.unauthorized();
    }

    var u = await query.updateOne();
    if (u == null) {
      return new Response.notFound();
    }

    return new Response.ok(u);
  }

  @Operation.delete("id")
  Future<Response> deleteUser(@Bind.path("id") int id) async {
    if (request.authorization.resourceOwnerIdentifier != id) {
      return new Response.unauthorized();
    }

    await authServer.revokeAuthenticatableAccessForIdentifier(id);
    var q = new Query<User>()..where.id = id;
    await q.delete();

    return new Response.ok(null);
  }
}
