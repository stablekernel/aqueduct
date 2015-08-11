part of monadart;

// Convenience methods for building pipelines
void addRouteController(Router router, String routePath, Type resourceControllerSubclass) {
  var stream = router.addRoute(routePath);
  stream.listen((req) {
    var controller = reflectClass(resourceControllerSubclass).newInstance(new Symbol(""), []).reflectee as ResourceController;
    controller.resourceRequest = req;
    controller.process();
  });
}