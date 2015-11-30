import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'package:monadart/monadart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../helpers.dart';
import 'package:postgresql/postgresql.dart';

void main() {
  QueryAdapter adapter;

  HttpServer server;

  tearDownAll(() async {
    await server.close();
  });

  setUp(() async {
    adapter = new PostgresModelAdapter(null, () async {
      var uri = 'postgres://dart:dart@localhost:5432/dart_test';
      return await connect(uri);
    });

    var authenticationServer = new AuthenticationServer<TestUser, Token>(
        new AuthDelegate<TestUser, Token>(adapter));

    HttpServer
        .bind("localhost", 8080,
          v6Only: false, shared: false)
          .then((s)
    {
      server = s;
      server.listen((req) {
        var resReq = new ResourceRequest(req);
        var authController = new AuthController<TestUser, Token>(authenticationServer);

        authController.deliver(resReq);
      });
    });

    await generateTemporarySchemaFromModels(adapter, [TestUser, Token]);
  });

  tearDown(() {
    server.close(force: true);
    adapter.close();
    adapter = null;
  });

  test("POST token responds with token on correct input", () async {
    await createUsers(adapter, 1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    var body = "";
    m.forEach((k, v) {
      body += "$k=${Uri.encodeQueryComponent(v)}&";
    });

    var res = await http.post("http://localhost:8080/auth/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: body);

    var json = JSON.decode(res.body);
    expect(json["access_token"].length, greaterThan(0));
    expect(json["refresh_token"].length, greaterThan(0));
    expect(json["expires_in"], greaterThan(3500));
    expect(json["token_type"], "bearer");
  });

  test("POST token header failure cases", () async {
    await createUsers(adapter, 1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    var body = "";
    m.forEach((k, v) {
      body += "$k=${Uri.encodeQueryComponent(v)}&";
    });

    var res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded"},
        body: body);
    expect(res.statusCode, 401);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "foobar"},
        body: body);
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic bad"},
        body: body);
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("foobar".codeUnits)}"},
        body: body);
    expect(res.statusCode, 400);
  });

  test("POST token body failure cases", () async {
    var encoder = (Map m) {
      var str = "";
      m.forEach((k, v) {
        str += "$k=${Uri.encodeQueryComponent(v)}&";
      });
      return str;
    };

    await createUsers(adapter, 2);

    var res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"}));
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"grant_type" : "foobar", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"}));
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"grant_type" : "password", "password" : "foobaraxegrind21%"}));
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"grant_type" : "password", "username" : "bob+24@stablekernel.com", "password" : "foobaraxegrind21%"}));
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"grant_type" : "password", "username" : "bob+0@stablekernel.com"}));
    expect(res.statusCode, 400);

    res = await http.post("http://localhost:8080/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: encoder({"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "fobar%"}));
    expect(res.statusCode, 401);
  });

  test("Refresh token responds with token on correct input", () async {
    await createUsers(adapter, 1);

    var m = {"grant_type" : "password", "username" : "bob+0@stablekernel.com", "password" : "foobaraxegrind21%"};
    var body = "";
    m.forEach((k, v) {
      body += "$k=${Uri.encodeQueryComponent(v)}&";
    });

    var res = await http.post("http://localhost:8080/auth/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: body);

    var json = JSON.decode(res.body);

    m = {"grant_type" : "refresh", "refresh_token" : json["refresh_token"]};
    body = "";
    m.forEach((k, v) {
      body += "$k=${Uri.encodeQueryComponent(v)}&";
    });
    res = await http.post("http://localhost:8080/auth/token",
        headers: {"Content-Type" : "application/x-www-form-urlencoded",
          "Authorization" : "Basic ${CryptoUtils.bytesToBase64("com.stablekernel.app1:kilimanjaro".codeUnits)}"},
        body: body);

    expect(res.statusCode, 200);
    json = JSON.decode(res.body);

    expect(json["access_token"].length, greaterThan(0));
    expect(json["refresh_token"].length, greaterThan(0));
    expect(json["expires_in"], greaterThan(3500));
    expect(json["token_type"], "bearer");
  });
}

