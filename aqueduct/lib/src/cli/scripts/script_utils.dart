List<String> importsForPackage(String packageName) => [
      "package:aqueduct/aqueduct.dart",
      "package:runtime/runtime.dart",
      "package:$packageName/$packageName.dart"
    ];
