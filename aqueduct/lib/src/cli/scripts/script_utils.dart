List<String> importsForPackage(String packageName) => [
      "package:aqueduct/aqueduct.dart",
      "package:$packageName/$packageName.dart",
      "package:runtime/runtime.dart"
    ];
