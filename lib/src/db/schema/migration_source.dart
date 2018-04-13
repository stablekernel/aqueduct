import 'package:analyzer/analyzer.dart';
import 'package:crypto/crypto.dart';

class MigrationSource {
  MigrationSource(this.source, this.uri, int nameStartIndex, int nameEndIndex) {
    originalName = source.substring(nameStartIndex, nameEndIndex);
    name = "M" + md5.convert(source.codeUnits).toString();
    source = source.replaceRange(nameStartIndex, nameEndIndex, name);
  }

  MigrationSource.fromMap(Map<String, dynamic> map) {
    originalName = map["originalName"];
    source = map["source"];
    name = map["name"];
    uri = map["uri"];
  }

  factory MigrationSource.fromFile(Uri uri) {
    try {
      final fileUnit = parseDartFile(uri.path);

      final sources = fileUnit.declarations
        .where((u)
      => u is ClassDeclaration)
        .map((cu)
      => cu as ClassDeclaration)
        .where((ClassDeclaration classDecl)
      {
        return classDecl.extendsClause.superclass.name.name == "Migration";
      }).map((cu)
      {
        final code = cu.toSource();
        final offset = cu.name.offset - cu.offset;
        return new MigrationSource(code, uri, offset, offset + cu.name.length);
      }).toList();

      if (sources.length != 1) {
        throw new StateError("Invalid migration file. Must contain exactly one 'Migration' subclass. File: '$uri'.");
      }
      return sources.first;
    } catch (_) {
      throw new StateError("Migration file '${uri.path}' failed to compile. If this file was generated and required additional input, "
        "search for the phrase '<<set>>' in the file and replace it with an appropriate expression.");
    }
  }

  Map<String, dynamic> asMap() {
    return {
      "originalName": originalName,
      "name": name,
      "source": source,
      "uri": uri
    };
  }

  static String combine(List<MigrationSource> sources) {
    return sources.map((s) => s.source).join("\n");
  }

  static int versionNumberFromUri(Uri uri) {
    var fileName = uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  String source;

  String originalName;

  String name;

  Uri uri;

  int get versionNumber => versionNumberFromUri(uri);
}
