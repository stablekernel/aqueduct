/*
Copyright (c) 2016, Stable Kernel LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/// A server-side framework built for productivity and testability.
///
/// This library is made up of a handful of modules for common functionality needed in building a web server.
///
/// There are four primary modules in this library.
///
/// auth: Has classes for implementing OAuth 2.0 behavior. Classes in this module all begin with the word 'Auth'.
///
/// db: Exposes an ORM. Classes in this module begin with 'Managed', 'Schema', 'Query' and 'Persistent'.
///
/// http: Classes for building HTTP request and response logic. Classes in this module often begin with 'HTTP'.
///
/// application: Classes in this module begin with 'Application' and are responsible for starting and stopping web servers on a number of isolates.
library aqueduct;

export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';

export 'src/application/application.dart';
export 'src/auth/auth.dart';
export 'src/commands/cli_command.dart';
export 'src/db/db.dart';
export 'src/http/http.dart';
export 'src/utilities/mock_server.dart';
export 'src/utilities/pbkdf2.dart';
export 'src/utilities/test_client.dart';
export 'src/utilities/test_matchers.dart';
