import '../wildfire.dart';

class User extends ManagedObject<_User> implements _User, AuthenticatableManagedObject {
  @managedTransientInputAttribute
  String password;

  String get username => email;
  void set username(un) {
    email = un;
  }
}

class _User {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(unique: true, indexed: true)
  String email;

  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;

  @ManagedColumnAttributes(omitByDefault: true)
  String salt;
}
