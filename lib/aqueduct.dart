/*
Copyright (c) 2016, Stable Kernel LLC
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

/// Core libraries for Aqueduct applications.
///
/// The library contains behavior for building REST server applications.
/// Some of the functionality includes routing requests to controllers, OAuth 2.0 and an ORM.
///
/// Please see documentation guides at https://aqueduct.io/docs/.
///
/// See the tutorial at https://aqueduct.io/docs/tut/getting-started/.
///
/// An example Aqueduct application:
///
///       class Channel extends ApplicationChannel {
///
///         @override
///         RequestController get entryPoint {
///           final router = new Router();
///
///           router
///             .route("/ok")
///             .listen((req) async {
///               return new Response.ok(null);
///             });
///
///           return router;
///         }
///       }
library aqueduct;

export 'package:logging/logging.dart';
export 'package:safe_config/safe_config.dart';

export 'src/application/application.dart';
export 'src/auth/auth.dart';
export 'src/db/db.dart';
export 'src/http/http.dart';
export 'src/utilities/resource_registry.dart';

