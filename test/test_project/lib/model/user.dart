import '../wildfire.dart';

class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner {
  @managedTransientInputAttribute
  String password;
}

class _User extends ManagedAuthenticatable {
  @ManagedColumnAttributes(unique: true)
  String email;

/* This class inherits the following from ManagedAuthenticatable:

  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(unique: true, indexed: true)
  String username;

  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;

  @ManagedColumnAttributes(omitByDefault: true)
  String salt;

  ManagedSet<ManagedAuthCode> authorizationCodes;
  ManagedSet<ManagedToken> tokens;
 */
}
