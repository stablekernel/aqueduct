- For bug fixes, please file an issue or submit a pull request to master. 
- For documentation improvements (typos, errors, etc.), please submit a pull request to the branch `docs/source`.
- For new features that are not already identified in issues, please file a new issue to discuss.

## Pull Request Requirements

Please document the intent of the pull request. All non-documentation pull requests must also include automated tests that cover the new code, including failure cases. If applicable, please update the documentation in the `docs/source` branch.

## Running Tests

Tests will automatically be run when you submit a pull request, but you will need to run tests locally. You must have a local PostgreSQL server with a database created with the following:

```bash
psql -c 'create user dart with createdb;' -U postgres
psql -c "alter user dart with password 'dart';" -U postgres
psql -c 'create database dart_test;' -U postgres
psql -c 'grant all on database dart_test to dart;' -U postgres
```

Run all tests with the following command:

                pub run test -j 1
