import 'dart:io';
import 'dart:async';
import 'package:logging/logging.dart';

class HTMLRenderer {
  Logger logger = new Logger("wildfire");
  Map<String, String> _cache = {};

  Future<String> renderHTML(
      String path, Map<String, dynamic> templateVariables) async {
    var template = await _loadHTMLTemplate(path);

    return template.replaceAllMapped("\\{\\{(a-zA-Z_)+\\}\\}", (match) {
      var key = match.group(1);
      return templateVariables[key] ?? "null";
    });
  }

  Future<String> _loadHTMLTemplate(String path) async {
    var contents = _cache[path];
    if (contents == null) {
      try {
        var file = new File(path);
        contents = file.readAsStringSync();
        _cache[path] = contents;
      } catch (e) {
        logger.warning("Could not read HTML template at '$path'.");
      }
    }

    return contents ?? "";
  }
}
