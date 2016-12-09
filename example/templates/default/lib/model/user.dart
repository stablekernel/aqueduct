import '../wildfire.dart';

class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwner {
  @managedTransientInputAttribute
  String password;
}

class _User extends ManagedAuthenticatable {

}
