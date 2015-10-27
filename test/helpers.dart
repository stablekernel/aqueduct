import 'dart:async';
import 'package:inquirer_pgsql/inquirer_pgsql.dart';
import 'package:monadart/monadart.dart';

Future<List<TestUser>> createUsers(PostgresModelAdapter adapter, int count) async {
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

@ModelBacking(UserBacking)
@proxy
class TestUser extends Object with Model implements UserBacking {
  noSuchMethod(inv) => super.noSuchMethod(inv);
}

class UserBacking implements Authenticatable {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String username;
  String hashedPassword;
  String salt;
}

@ModelBacking(TokenBacking)
@proxy
class Token extends Object with Model implements TokenBacking {
  noSuchMethod(inv) => super.noSuchMethod(inv);
}

class TokenBacking implements Tokenizable {
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
  PostgresModelAdapter adapter;

  AuthDelegate(this.adapter);

  Future<T> tokenForAccessToken(String accessToken) {
    return _tokenForPredicate(new Predicate("accessToken = @accessToken", {"accessToken" : accessToken}));
  }

  Future<T> tokenForRefreshToken(String refreshToken) {
    return _tokenForPredicate(new Predicate("refreshToken = @refreshToken", {"refreshToken" : refreshToken}));
  }

  Future<User> authenticatableForUsername(String username) {
    var userQ = new Query<User>();
    userQ.predicate = new Predicate("username = @username", {"username" : username});
    return userQ.fetchOne(adapter);
  }

  Future<User> authenticatableForID(int id) {
    var userQ = new Query<User>();
    userQ.predicate = new Predicate("username = @username", {"id" : id});
    return userQ.fetchOne(adapter);
  }

  Future deleteTokenForAccessToken(String accessToken) async {
    var q = new Query<T>();
    q.predicate = new Predicate("accessToken = @ac", {"ac" : accessToken});
    await q.delete(adapter);
  }

  Future storeToken(T t) async {
    var tokenQ = new Query<T>();
    tokenQ.valueObject = t;
    await tokenQ.insert(adapter);
  }

  Future pruneTokensForResourceOwnerID(dynamic id) async {
    return null;
  }

  Future<T> _tokenForPredicate(Predicate p) async {
    var tokenQ = new Query<T>();
    tokenQ.predicate = p;
    var result = await tokenQ.fetchOne(adapter);
    if (result == null) {
      throw new AuthenticationServerException("Invalid token", 401);
    }

    return result;
  }
}