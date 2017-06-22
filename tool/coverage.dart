import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:coverage/coverage.dart';

Future main(List<String> args) async {
  try {
    var tempDir = new Directory("coverage_json/");
    var outputDir = new Directory("coverage/");
    var testDir = new Directory("test/");
    List<Directory> splitTestDirs = testDir.listSync()
      .where((f) => f is Directory)
      .map((f) => f as Directory)
      .toList();

    var slice = Platform.environment["COVERAGE_SLICE"];
    if (slice != null) {
      var dirs = slice.split(" ");
      splitTestDirs = splitTestDirs.where((dir) {
        return dirs.any((d) => dir.path.endsWith("$d"));
      }).toList();
    }

    var testFiles = splitTestDirs
        .expand((d) => d.listSync(recursive: true))
        .where((f) => f is File && f.path.endsWith("_test.dart"))
        .map((f) => f as File)
        .toList();

    tempDir.createSync();
    outputDir.createSync();

    var count = 0;
    await Future.forEach(testFiles, (File file) async {
      print("Running ${file.uri.pathSegments.last} (${count + 1} of ${testFiles.length})...");
      var coverage = await runAndCollect(file.path, outputSink: stdout);
      print("All coverage collected for ${file.uri.pathSegments.last}.");

      var fileHash = md5.convert(file.path.codeUnits);
      var coverageJSONFile = new File.fromUri(tempDir.uri.resolve("${fileHash.toString()}.coverage.json"));
      coverageJSONFile.writeAsStringSync(JSON.encode(coverage));

      count ++;
    });

    var totalTestFiles = testDir
        .listSync(recursive: true)
        .where((f) => f is File && f.path.endsWith("_test.dart"))
        .length;
    var totalCoverageFiles = tempDir
        .listSync()
        .where((f) => f is File && f.path.endsWith("json"))
        .length;

    print("There are ${totalTestFiles} total test files and ${totalCoverageFiles} coverage files.");
    if (totalTestFiles == totalCoverageFiles) {
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

      tempDir
          .listSync()
          .forEach((f) {
            f.deleteSync(recursive: true);
          });
    } else {
      print("Waiting for other stages to complete before sending test coverage.");
    }
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