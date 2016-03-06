@TestOn("vm")
import "package:test/test.dart";
import "dart:core";
import "dart:io";
import 'package:http/http.dart' as http;
import 'package:monadart/monadart.dart';
import 'dart:convert';
import 'dart:async';

void main() {

  HttpServer server;

  setUp(() {
  });

  tearDown(() async {
    if (server != null) {
      await server.close();
    }
  });

  tearDownAll(() async {
    if (server != null) {
      await server.close();
    }
  });
}
