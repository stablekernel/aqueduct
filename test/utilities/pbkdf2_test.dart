import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';

main() {
  test("Throw exception if hash function derived key length exceeds max int", () {
    var hLen = sha1.convert([1]).bytes.length;
    var gen = new PBKDF2(hashFunction: sha1);

    try {
      gen.generateKey("password", "salt", 1, (pow(2, 32) - 1) * hLen + 1);
      expect(true, false);
    } on PBKDF2Exception {}
  });

  test("RFC6070 test vectors 1", () {
    var bytes = new PBKDF2(hashFunction: sha1).generateKey("password", "salt", 1, 20);
    var expectedBytes = "0c 60 c8 0f 96 1f 0e 71 f3 a9 b5 24 af 60 12 06 2f e0 37 a6"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });

  test("RFC6070 test vectors 2", () {
    var bytes = new PBKDF2(hashFunction: sha1).generateKey("password", "salt", 2, 20);
    var expectedBytes = "ea 6c 01 4d c7 2d 6f 8c cd 1e d9 2a ce 1d 41 f0 d8 de 89 57"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });

  test("RFC6070 test vectors 3", () {
    var bytes = new PBKDF2(hashFunction: sha1).generateKey("password", "salt", 4096, 20);
    var expectedBytes = "4b 00 79 01 b7 65 48 9a be ad 49 d9 26 f7 21 d0 65 a4 29 c1"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });

  test("RFC6070 test vectors 4", () {
    print("Note: this test takes a few minutes.");

    var bytes = new PBKDF2(hashFunction: sha1).generateKey("password", "salt", 16777216, 20);
    var expectedBytes = "ee fe 3d 61 cd 4d a4 e4 e9 94 5b 3d 6b a2 15 8c 26 34 e9 84"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });

  test("RFC6070 test vectors 5", () {
    var bytes = new PBKDF2(hashFunction: sha1).generateKey("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 4096, 25);
    var expectedBytes = "3d 2e ec 4f e4 1c 84 9b 80 c8 d8 36 62 c0 e4 4a 8b 29 1a 96 4c f2 f0 70 38"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });

  test("RFC6070 test vectors 6", () {
    var bytes = new PBKDF2(hashFunction: sha1).generateKey("pass\u0000word", "sa\u0000lt", 4096, 16);
    var expectedBytes = "56 fa 6a a7 55 48 09 9d cc 37 d7 f0 34 25 e0 c3"
        .split(" ")
        .map((byte) => int.parse(byte, radix: 16))
        .toList();

    expect(bytes, expectedBytes);
  });
}