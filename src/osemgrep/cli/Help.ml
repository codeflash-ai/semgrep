(* Yoann Padioleau
 *
 * Copyright (C) 2023 Semgrep Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file LICENSE.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * LICENSE for more details.
 *)

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Help message for 'semgrep --help' (or just 'semgrep')
 *
 * python: the help message was automatically generated by Click
 * based on the docstring and the subcommands. In OCaml we have to
 * generate it manually, but anyway we want full control of the help
 * message so this isn't too bad.
 *)

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

(* LATER: add 'interactive', 'test', 'validate', and 'dump' new osemgrep-only
 * subcommands (not added yet to avoid regressions in tests/e2e/test_help.py).
 *)
let print_semgrep_help () =
  print_string
    {|
┌──── ○○○ ────┐
│ Semgrep CLI │
└─────────────┘
Semgrep CLI scans your code for bugs, security and dependency vulnerabilities.

For more information about Semgrep, visit https://semgrep.dev

Get Started:
  Run `semgrep login && semgrep ci` to find dependency
  vulnerabilities and advanced cross-file findings. 💎

Commands:
  semgrep ci                   The recommended way to run semgrep in CI
  semgrep scan                 Run semgrep rules on files

Advanced Commands:
  semgrep install-semgrep-pro  Install the Semgrep Pro Engine (recommended)
  semgrep login                Obtain and save credentials for semgrep.dev
  semgrep logout               Remove locally stored credentials to
                               semgrep.dev

Help:
  semgrep COMMAND --help       For more information on each command

For the CLI docs visit https://semgrep.dev/docs/category/semgrep-cli/
|}
