import '../bin/monadart.dart';
import 'dart:io';

class TestRESTController extends RESTController {

  Response get(Request req, {String id}) {
    if(id != null) {
      return getPlayer(req, id);
    } else {
      return getAllPlayers(req);
    }
  }

  Response put(Request req) {
    throw new ArgumentError("missing args");
  }

  Response getPlayer(Request req, String id) {
    return new Response.ok("id=${id}");
  }

  Response getAllPlayers(Request req) {
    return new Response.ok("all");
  }
}