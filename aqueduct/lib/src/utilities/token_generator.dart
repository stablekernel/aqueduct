import 'dart:math';

String randomStringOfLength(int length) {
  var possibleCharacters =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  var buff = new StringBuffer();

  var r = new Random.secure();
  for (int i = 0; i < length; i++) {
    buff.write(
        "${possibleCharacters[r.nextInt(1000) % possibleCharacters.length]}");
  }

  return buff.toString();
}
