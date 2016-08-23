part of wildfire;

class UserQuery extends ModelQuery<User> implements _User {}
class User extends Model<_User> implements _User, Authenticatable {
  @mappableInput
  String password;

  String get username => email;
  void set username(un) {
    email = un;
  }
}

class _User {
  @primaryKey
  int id;

  @Attributes(unique: true, indexed: true)
  String email;

  @Attributes(omitByDefault: true)
  String hashedPassword;

  @Attributes(omitByDefault: true)
  String salt;

  @Relationship.hasMany("owner")
  List<Token> tokens;
}
