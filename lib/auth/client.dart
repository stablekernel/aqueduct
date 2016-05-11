part of aqueduct;

class Client {
  String id;
  String hashedSecret;
  String salt;

  Client(this.id, this.hashedSecret, this.salt);
}
