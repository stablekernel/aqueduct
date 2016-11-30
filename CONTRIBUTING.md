### Running Tests

A local database must exist, configured using the same script in .travis.yml.

Tests are run with the following command:

                pub run test -j 1

### Collecting Coverage

Install code_coverage:

                pub global activate coverage

Run the following script:

                dart tool/generate_test_all.dart test/test_all.dart

Then, run this generated script:

                dart --observe --checked test/test_all.dart

From another terminal, run collect coverage (replace port if the previous script reported using another port:

                collect_coverage --port=8181 -o coverage.json --resume-isolates

Once this command completes, format the coverage.json file into lcov:

                format_coverage --packages=.packages -l --report-on=lib -o coverage.lcov -i coverage.json

This file is best viewed using Atom and the lcov-info package.