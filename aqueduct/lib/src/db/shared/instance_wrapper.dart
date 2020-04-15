import 'package:aqueduct/aqueduct.dart';

class InstanceWrapper {
  // ignore: avoid_positional_boolean_parameters
  InstanceWrapper(this.instance, this.isNew);

  bool isNew;
  ManagedObject instance;
}
