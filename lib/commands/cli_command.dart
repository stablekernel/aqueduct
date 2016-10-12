part of aqueduct;

abstract class CLICommand {
  ArgParser get options;

  Future<int> handle(ArgResults results);

  Future cleanup() async {

  }

  Future<int> process(ArgResults results) async {
    try {
      var returnValue = await handle(results);
      await cleanup();
      return returnValue;
    } catch (e) {
      await cleanup();
      print("${e}");
    }
    return -1;
  }
}