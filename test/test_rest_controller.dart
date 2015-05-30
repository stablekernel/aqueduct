import '../bin/monadart.dart';
import 'dart:io';

class TestRESTController extends RESTController {
  get(HttpRequest req, {String id}) {
    if(id != null) {
      getPlayer(req, id);
    } else {
      getAllPlayers(req);
    }
  }

  put(HttpRequest req) {
    throw new ArgumentError("missing args");
  }

  getPlayer(HttpRequest req, String id) {
    req.response.statusCode = 200;
    req.response.write("id=${id}");
  }

  getAllPlayers(HttpRequest req) {
    req.response.statusCode = 200;
    req.response.write("all");
  }
}