import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("Generated confidential, redirectable API client has valid values", () {
    var client = AuthUtility.generateAPICredentialPair("a", "b",
        redirectURI: "http://a.com");
    expect(client.id, "a");
    expect(client.hashedSecret,
        AuthUtility.generatePasswordHash("b", client.salt));
    expect(client.redirectURI, "http://a.com");
  });

  test("Generated confidential, non-redirectable API client has valid values",
      () {
    var client = AuthUtility.generateAPICredentialPair("a", "b");
    expect(client.id, "a");
    expect(client.hashedSecret,
        AuthUtility.generatePasswordHash("b", client.salt));
    expect(client.redirectURI, isNull);
  });

  test("Generated public API client has valid values", () {
    var client = AuthUtility.generateAPICredentialPair("a", null);
    expect(client.id, "a");
    expect(client.hashedSecret, isNull);
    expect(client.salt, isNull);
    expect(client.redirectURI, isNull);
  });

  test("Trying to generate public API that has redirect URL yields error", () {
    try {
      AuthUtility.generateAPICredentialPair("a", null,
          redirectURI: "http://a.com");
      expect(true, false);
    } on ArgumentError catch (e) {
      expect(e.message, contains("Invalid input"));
    }
  });
}
