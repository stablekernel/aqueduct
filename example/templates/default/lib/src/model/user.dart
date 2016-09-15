part of wildfire;

class User extends Model<_User> implements _User, Authenticatable {
  @transientInputAttribute
  String password;

  String get username => email;
  void set username(un) {
    email = un;
  }
}

class _User {
  @primaryKey
  int id;

  @AttributeHint(unique: true, indexed: true)
  String email;

  @AttributeHint(omitByDefault: true)
  String hashedPassword;

  @AttributeHint(omitByDefault: true)
  String salt;

  OrderedSet<Token> tokens;
}
