import '../wildfire.dart';

class User extends ManagedObject<_User> implements _User, ManagedAuthResourceOwnerType {
  @managedTransientInputAttribute
  String password;
}

class _User extends ManagedAuthenticatable {

}
