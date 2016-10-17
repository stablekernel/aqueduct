part of aqueduct;

/// A command line interface command.
abstract class CLICommand {
  /// Options for this command.
  ArgParser get options;

  /// Handles the command input.
  ///
  /// Override this method to perform actions for this command.
  ///
  /// Return value is the value returned to the command line operation. Return 0 for success.
  Future<int> handle(ArgResults results);

  /// Cleans up any resources used during this command.
  ///
  /// Delete temporary files or close down any [Stream]s.
  Future cleanup() async {

  }

  /// Invoked on this instance when this command is executed from the command line.
  ///
  /// Do not override this method. This method invokes [handle] within a try-catch block
  /// and will invoke [cleanup] when complete.
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