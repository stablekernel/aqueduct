import 'dart:async';
import 'package:aqueduct/aqueduct.dart';

Future<List<TestUser>> createUsers(QueryAdapter adapter, int count) async {
  var users = new List<TestUser>();
  for (int i = 0; i < count; i++) {
    var salt = AuthenticationServer.generateRandomSalt();
    var u = new TestUser()
      ..username = "bob+$i@stablekernel.com"
      ..salt = salt
      ..hashedPassword = AuthenticationServer.generatePasswordHash("foobaraxegrind21%", salt);

    var q = new Query<TestUser>()..valueObject = u;
    var insertedUser = await q.insert(adapter);
    users.add(insertedUser);
  }
  return users;
}

class TestUser extends Model<_User> implements _User {}

class _User implements Authenticatable {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String username;
  String hashedPassword;
  String salt;
}

class Token extends Model<_Token> implements _Token {}


class _Token implements Tokenizable {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  @Attributes(indexed: true)
  String accessToken;

  @Attributes(indexed: true)
  String refreshToken;

  DateTime issueDate;
  DateTime expirationDate;
  int resourceOwnerIdentifier;
  String type;
  String clientID;
}

class AuthDelegate<User extends Model, T extends Model> implements AuthenticationServerDelegate {
  QueryAdapter adapter;

  AuthDelegate(this.adapter);

  Future<T> tokenForAccessToken(AuthenticationServer server, String accessToken) {
    return _tokenForPredicate(new Predicate("accessToken = @accessToken", {"accessToken" : accessToken}));
  }

  Future<T> tokenForRefreshToken(AuthenticationServer server, String refreshToken) {
    return _tokenForPredicate(new Predicate("refreshToken = @refreshToken", {"refreshToken" : refreshToken}));
  }

  Future<User> authenticatableForUsername(AuthenticationServer server, String username) {
    var userQ = new Query<User>();
    userQ.predicate = new Predicate("username = @username", {"username" : username});
    return userQ.fetchOne(adapter);
  }

  Future<User> authenticatableForID(AuthenticationServer server, int id) {
    var userQ = new Query<User>();
    userQ.predicate = new Predicate("username = @username", {"id" : id});
    return userQ.fetchOne(adapter);
  }

  Future deleteTokenForAccessToken(AuthenticationServer server, String accessToken) async {
    var q = new Query<T>();
    q.predicate = new Predicate("accessToken = @ac", {"ac" : accessToken});
    await q.delete(adapter);
  }

  Future storeToken(AuthenticationServer server, T t) async {
    var tokenQ = new Query<T>();
    tokenQ.valueObject = t;
    await tokenQ.insert(adapter);
  }

  Future<Client> clientForID(AuthenticationServer server, String id) async {
    var salt = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345";
    if (id == "com.stablekernel.app1") {
      return new Client("com.stablekernel.app1", AuthenticationServer.generatePasswordHash("kilimanjaro", salt), salt);
    }
    if (id == "com.stablekernel.app2") {
      return new Client("com.stablekernel.app2", AuthenticationServer.generatePasswordHash("fuji", salt), salt);
    }

    return null;
  }

  Future pruneTokensForResourceOwnerID(AuthenticationServer server, dynamic id) async {
    return null;
  }

  Future<T> _tokenForPredicate(Predicate p) async {
    var tokenQ = new Query<T>();
    tokenQ.predicate = p;
    var result = await tokenQ.fetchOne(adapter);
    if (result == null) {
      throw new HttpResponseException(401, "Invalid Token");
    }

    return result;
  }
}