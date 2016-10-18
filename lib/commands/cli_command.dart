part of aqueduct;

abstract class CLICommand {
  ArgParser get options;

  Future<int> handle(ArgResults results);

  Future cleanup() async {

  }

  Future<int> process(ArgResults results) async {
    try {
      return await handle(results);
    } catch (e) {
      print("${e}");
    } finally {
      await cleanup();
    }
    return -1;
  }
}