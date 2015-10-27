part of monadart;

class Client {
  String id;
  String secret;
  String get base64 {
    var concat = "$id:$secret";
    return CryptoUtils.bytesToBase64(concat.codeUnits);
  }

  Client(this.id, this.secret);
}