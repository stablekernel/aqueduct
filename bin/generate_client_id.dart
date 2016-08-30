import 'package:aqueduct/aqueduct.dart';
import 'dart:mirrors';

void main(List<String> args) {
  if (args.length != 2) {
    print("Usage: pub global run aqueduct:generate_client_id client_id client_secret");
    return;
  }

  var clientID = args.first;
  var clientSecret = args.last;
  var salt = AuthenticationServer.generateRandomSalt();
  var hashed = AuthenticationServer.generatePasswordHash(clientSecret, salt);
  print("insert into _client (hashedPassword, id, salt) values ('$hashed', '$clientID', '$salt');");
}
