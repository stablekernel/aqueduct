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

  @ColumnAttributes(unique: true, indexed: true)
  String email;

  @ColumnAttributes(omitByDefault: true)
  String hashedPassword;

  @ColumnAttributes(omitByDefault: true)
  String salt;

  OrderedSet<Token> tokens;
}
