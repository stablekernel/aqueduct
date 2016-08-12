import 'dart:io';
import 'package:aqueduct/aqueduct.dart';

void main(List<String> args) {
  if (args.length != 2) {
    print("Usage: dart bin/generate_client_id.dart clientID clientSecret");
    return;
  }

  var clientID = args.first;
  var clientSecret = args.last;
  var salt = AuthenticationServer.generateRandomSalt();
  var hashed = AuthenticationServer.generatePasswordHash(clientSecret, salt);
  print("insert into _client (hashedPassword, id, salt) values ('$hashed', '$clientID', '$salt');");
}
