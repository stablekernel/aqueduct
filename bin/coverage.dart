import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:coverage/coverage.dart';

Future main(List<String> args) async {
  try {
    var tempDir = new Directory("coverage_json/");
    var outputDir = new Directory("coverage/");
    var testDir = new Directory("test/");
    var testFiles = testDir
        .listSync(recursive: true)
        .where((f) => f is File && f.path.endsWith("_test.dart"))
        .map((f) => f as File)
        .toList();

    tempDir.createSync();
    outputDir.createSync();

    var count = 0;
    for (var file in testFiles) {
      print("Running ${file.uri.pathSegments.last} (${count + 1} of ${testFiles.length})...");
      var coverage = await runAndCollect(file.path, outputBuffer: stdout);

      var coverageJSONFile = new File.fromUri(tempDir.uri.resolve("$count.coverage.json"));
      coverageJSONFile.writeAsStringSync(JSON.encode(coverage));

      count ++;
    }

    print("Formatting coverage...");
    var hitmap = await parseCoverage(tempDir
        .listSync()
        .where((f) => f.path.endsWith("coverage.json"))
        .map((f) => f as File), 1);

    print("Converting to lcov...");
    var lcovFormatter = new LcovFormatter(new Resolver(packagesPath: ".packages"), reportOn: ["lib/"]);
    var output = await lcovFormatter.format(hitmap);
    var outputFile = new File.fromUri(outputDir.uri.resolve("lcov.info"));
    outputFile.writeAsStringSync(output);

    tempDir.deleteSync(recursive: true);
  } catch (e, st) {
    print("$e");
    print("$st");
    exitCode = 1;
  }
}

Map<String, dynamic> onlyFromSource(Map<String, dynamic> initialCoverage, String sourcePrefix) {
  List<Map<String, dynamic>> coverage = initialCoverage["coverage"];
  var filteredList = coverage.where(((coverObj) {
    String source = coverObj["source"];
    return source.startsWith(sourcePrefix);
  })).toList();
  
  initialCoverage["coverage"] = filteredList;
  return initialCoverage;
}