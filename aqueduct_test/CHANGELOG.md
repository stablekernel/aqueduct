## 1.0.1

- Fixes analysis warnings for Dart 2.1.1

## 1.0.0+1

- Bumps some dependency constraints to be more permissive

## 1.0.0

- Initial version from `package:aqueduct`.
- Adds `TestHarness` base class for test harnesses.
- Adds `TestHarnessORMMixin` for testing ORM applications.
- Adds `TestHarnessAuthMixin` for testing OAuth2 applications.
- Renames `TestClient` to `Agent` and adds methods for executing requests without constructing a `TestRequest`.
- Adds default parameters to `Agent` for its requests.