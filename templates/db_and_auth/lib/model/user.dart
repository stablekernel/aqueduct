import '../wildfire.dart';

class User extends ManagedObject<_User>
    implements _User, ManagedAuthResourceOwner {
  @Serialize(input: true, output: false)
  String password;
}

class _User extends ManagedAuthenticatable {
  @Column(unique: true)
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

  ManagedSet<ManagedAuthToken> tokens;
 */
}
