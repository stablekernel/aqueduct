part of aqueduct;

abstract class CLICommand {
  ArgParser get options;

  Future<int> handle(ArgResults results);

  Future<int> process(ArgResults results) async {
    try {
      return await handle(results);
    } catch (e) {
      print("${e}");
    }
    return -1;
  }
}