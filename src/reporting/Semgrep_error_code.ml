(*
 * Copyright (C) 2021 r2c
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
open Common
module Out = Output_from_core_j
module R = Rule

let logger = Logging.get_logger [ __MODULE__ ]

(****************************************************************************)
(* Prelude *)
(****************************************************************************)
(* Error management for semgrep-core.
 *)

(****************************************************************************)
(* Types and globals *)
(****************************************************************************)

(* See also try_with_exn_to_errors(), try_with_error_loc_and_reraise(), and
 * filter_maybe_parse_and_fatal_errors.
 * less: we should define everything in Output_from_core.atd, not just typ:
 *)
type error = {
  rule_id : Rule_ID.t option;
  typ : Out.core_error_kind;
  loc : Tok.location;
  msg : string;
  details : string option;
}
[@@deriving show]

(*
   Error accumulators.
   TODO: explain why they're global or make them not global.
*)
let g_errors = ref ([] : error list)
let g_incompatible_rules = ref ([] : Out.incompatible_rule list)

(****************************************************************************)
(* Convertor functions *)
(****************************************************************************)

(*
   Type used when sorting internal exceptions and turning them
   into their own list in the response.

   For example, having an "incompatible rule" is not really an error but
   should result in a specific behavior in the client app such as
   inviting the user to upgrade their Semgrep. It's easier for the
   user of the API if we provide a dedicated record field for this condition
   rather than having them sort through the error list. Conversely, if they
   don't care about the different kinds of things that went wrong,
   it's comparatively easier to compute length(errors)
   + length(incompatible_rules).

   The rationale for keeping different kinds of errors segregated is that
   in practice, it's generally easier to mix elements from multiple sets
   than to unmix/classify them, similarly to how it's easier to print an AST
   than to parse a string into an AST:

     easy: structured/sorted/ordered/low-entropy -> unordered/high-entropy
           e.g. list concatenation
     hard: unordered/high-entropy -> structured/sorted/ordered/low-entropy
           e.g. partitioning a list based on the properties of its elements
*)
type error_class = Error of error | Incompatible_rule of Out.incompatible_rule

(* more compact/readable than what's derived by ppx show *)
let string_of_incompatible_rule (x : Out.incompatible_rule) =
  spf
    "incompatible rule %s: this Semgrep version is %s but the rule requires%s%s"
    x.rule_id x.this_version
    (match x.min_version with
    | None -> ""
    | Some version -> spf " (>= %s)" version)
    (match x.max_version with
    | None -> ""
    | Some version -> spf " (<= %s)" version)

let push_error_class (x : error_class) =
  match x with
  | Error err -> Common.push err g_errors
  | Incompatible_rule x -> Common.push x g_incompatible_rules

let please_file_issue_text =
  "An error occurred while invoking the Semgrep engine. Please help us fix \
   this by creating an issue at https://github.com/returntocorp/semgrep"

let mk_error ?(rule_id = None) loc msg err =
  let msg =
    match err with
    | Out.MatchingError
    | Out.AstBuilderError
    | Out.FatalError
    | Out.TooManyMatches ->
        Printf.sprintf "%s\n\n%s" please_file_issue_text msg
    | LexicalError
    | ParseError
    | SpecifiedParseError
    | RuleParseError
    | InvalidYaml
    | SemgrepMatchFound
    | Timeout
    | OutOfMemory
    | TimeoutDuringInterfile
    | OutOfMemoryDuringInterfile
    | PatternParseError _
    | PartialParsing _ ->
        msg
  in
  { rule_id; loc; typ = err; msg; details = None }

let mk_error_tok ?(rule_id = None) tok msg err =
  let loc = Tok.unsafe_loc_of_tok tok in
  mk_error ~rule_id loc msg err

let error rule_id loc msg err =
  Common.push (mk_error ~rule_id:(Some rule_id) loc msg err) g_errors

(*
   This function converts known exceptions to Semgrep errors.
   We also use it to register global exception printers for
   'Printexc.to_string' to show useful messages.

   TODO: why not capture AST_generic.error here? So we could get rid
   of Run_semgrep.exn_to_error wrapper.
*)
let known_exn_to_error_class ?(rule_id = None) file (e : Exception.t) :
    error_class option =
  match Exception.get_exn e with
  (* TODO: Move the cases handling Parsing_error.XXX to the Parsing_error
     module so that we can use it for the exception printers that are
     registered there. *)
  | Parsing_error.Lexical_error (s, tok) ->
      Some (Error (mk_error_tok ~rule_id tok s Out.LexicalError))
  | Parsing_error.Syntax_error tok ->
      let msg =
        match tok with
        | Tok.OriginTok { str = ""; _ } ->
            (* TODO: at least in some cases, this comes from a MISSING node
               inserted by tree-sitter. These are reported as errors
               with a good error message that was lost.
               We should preserve the original error message. *)
            "missing element"
        | Tok.OriginTok { str; _ } -> spf "`%s` was unexpected" str
        | __else__ -> "unknown reason"
      in
      Some (Error (mk_error_tok tok msg Out.ParseError))
  | Parsing_error.Other_error (s, tok) ->
      Some (Error (mk_error_tok ~rule_id tok s Out.SpecifiedParseError))
  | R.Err err -> (
      match err with
      | R.InvalidRule
          (R.InvalidPattern (pattern, xlang, message, yaml_path), rule_id, pos)
        ->
          Some
            (Error
               {
                 rule_id = Some rule_id;
                 typ = Out.PatternParseError yaml_path;
                 loc = Tok.unsafe_loc_of_tok pos;
                 msg =
                   spf
                     "Invalid pattern for %s:\n\
                      --- pattern ---\n\
                      %s\n\
                      --- end pattern ---\n\
                      Pattern error: %s\n"
                     (Xlang.to_string xlang) pattern message;
                 details = None;
               })
      | R.InvalidRule (kind, rule_id, pos) -> (
          match kind with
          | IncompatibleVersion (this_version, (min_version, max_version)) ->
              Some
                (Incompatible_rule
                   {
                     rule_id = (rule_id :> string);
                     this_version = Version_info.to_string this_version;
                     min_version = Option.map Version_info.to_string min_version;
                     max_version = Option.map Version_info.to_string max_version;
                     location = Output_from_core_util.location_of_token pos;
                   })
          | _ ->
              let msg = Rule.string_of_invalid_rule_error_kind kind in
              Some
                (Error
                   (mk_error_tok ~rule_id:(Some rule_id) pos msg
                      Out.RuleParseError)))
      | R.InvalidYaml (msg, pos) ->
          Some (Error (mk_error_tok ~rule_id pos msg Out.InvalidYaml))
      | R.DuplicateYamlKey (s, pos) ->
          Some (Error (mk_error_tok ~rule_id pos s Out.InvalidYaml))
      (* TODO?? *)
      | R.UnparsableYamlException _ -> None)
  | Time_limit.Timeout timeout_info ->
      let s = Printexc.get_backtrace () in
      logger#error "WEIRD Timeout converted to exn, backtrace = %s" s;
      (* This exception should always be reraised. *)
      let loc = Tok.first_loc_of_file file in
      let msg = Time_limit.string_of_timeout_info timeout_info in
      Some (Error (mk_error ~rule_id loc msg Out.Timeout))
  | Memory_limit.ExceededMemoryLimit msg ->
      let loc = Tok.first_loc_of_file file in
      Some (Error (mk_error ~rule_id loc msg Out.OutOfMemory))
  | Out_of_memory ->
      let loc = Tok.first_loc_of_file file in
      Some (Error (mk_error ~rule_id loc "Heap space exceeded" Out.OutOfMemory))
  (* general case, can't extract line information from it, default to line 1 *)
  | _exn -> None

let exn_to_error_class ?(rule_id = None) file (e : Exception.t) : error_class =
  match known_exn_to_error_class ~rule_id file e with
  | Some err -> err
  | None -> (
      match Exception.get_exn e with
      | UnixExit _ ->
          (* TODO: remove this.
             This exception shouldn't be passed to this function
             in the first place. *)
          Exception.reraise e
      | exn ->
          let trace = Exception.to_string e in
          let loc = Tok.first_loc_of_file file in
          Error
            {
              rule_id;
              typ = Out.FatalError;
              loc;
              msg = Printexc.to_string exn;
              details = Some trace;
            })

let exn_to_error_lists ?rule_id file exn =
  match exn_to_error_class ?rule_id file exn with
  | Error x -> ([ x ], [])
  | Incompatible_rule x -> ([], [ x ])

(*****************************************************************************)
(* Pretty printers *)
(*****************************************************************************)

let source_of_string = function
  | "" -> "<input>"
  | path -> path

let string_of_error err =
  let pos = err.loc in
  let details =
    match err.details with
    | None -> ""
    | Some s -> spf "\n%s" s
  in
  spf "%s:%d:%d: %s: %s%s"
    (source_of_string pos.Tok.pos.file)
    pos.Tok.pos.line pos.Tok.pos.column
    (Out.string_of_core_error_kind err.typ)
    err.msg details

let string_of_error_class err_c =
  match err_c with
  | Error err -> string_of_error err
  | Incompatible_rule x -> string_of_incompatible_rule x

let severity_of_error typ =
  match typ with
  | Out.SemgrepMatchFound -> Out.Error
  | Out.MatchingError -> Warning
  | Out.TooManyMatches -> Warning
  | Out.LexicalError -> Warning
  | Out.ParseError -> Warning
  | Out.PartialParsing _ -> Warning
  | Out.SpecifiedParseError -> Warning
  | Out.AstBuilderError -> Error
  | Out.RuleParseError -> Error
  | Out.PatternParseError _ -> Error
  | Out.InvalidYaml -> Warning
  | Out.FatalError -> Error
  | Out.Timeout -> Warning
  | Out.OutOfMemory -> Warning
  | Out.TimeoutDuringInterfile -> Error
  | Out.OutOfMemoryDuringInterfile -> Error

(*****************************************************************************)
(* Try with error *)
(*****************************************************************************)

let try_with_exn_to_error_class file f =
  try f () with
  | Time_limit.Timeout _ as exn -> Exception.catch_and_reraise exn
  | exn ->
      let e = Exception.catch exn in
      exn_to_error_class file e |> push_error_class

let try_with_print_exn_and_reraise file f =
  try f () with
  | Time_limit.Timeout _ as exn -> Exception.catch_and_reraise exn
  | exn ->
      let e = Exception.catch exn in
      let err = exn_to_error_class file e in
      pr2 (string_of_error_class err);
      Exception.reraise e

(*****************************************************************************)
(* Helper functions to use in testing code *)
(*****************************************************************************)

let default_error_regexp = ".*\\(ERROR\\|MATCH\\):"

let (expected_error_lines_of_files :
      ?regexp:string ->
      ?ok_regexp:string option ->
      Common.filename list ->
      (Common.filename * int) (* line *) list) =
 fun ?(regexp = default_error_regexp) ?(ok_regexp = None) test_files ->
  test_files
  |> List.concat_map (fun file ->
         Common.cat file |> Common.index_list_1
         |> Common.map_filter (fun (s, idx) ->
                (* Right now we don't care about the actual error messages. We
                 * don't check if they match. We are just happy to check for
                 * correct lines error reporting.
                 *)
                if
                  s =~ regexp (* + 1 because the comment is one line before *)
                  (* This is so that we can mark a line differently for OSS and Pro,
                     e.g. `ruleid: deepok: example_rule_id` *)
                  && Option.fold ~none:true
                       ~some:(fun ok_regexp -> not (s =~ ok_regexp))
                       ok_regexp
                then Some (file, idx + 1)
                else None))

(* A copy-paste of Error_code.compare_actual_to_expected but
 * with Semgrep_error_code.error instead of Error_code.t for the error type.
 *)
let compare_actual_to_expected actual_findings expected_findings_lines =
  let actual_findings_lines =
    actual_findings
    |> Common.map (fun err ->
           let loc = err.loc in
           (loc.Tok.pos.file, loc.Tok.pos.line))
  in
  (* diff report *)
  let _common, only_in_expected, only_in_actual =
    Common2.diff_set_eff expected_findings_lines actual_findings_lines
  in

  only_in_expected
  |> List.iter (fun (src, l) ->
         pr2 (spf "this one finding is missing: %s:%d" src l));
  only_in_actual
  |> List.iter (fun (src, l) ->
         pr2
           (spf "this one finding was not expected: %s:%d (%s)" src l
              (actual_findings
              (* nosemgrep: ocaml.lang.best-practice.list.list-find-outside-try *)
              |> List.find (fun err ->
                     let loc = err.loc in
                     src = loc.Tok.pos.file && l =|= loc.Tok.pos.line)
              |> string_of_error)));
  let num_errors = List.length only_in_actual + List.length only_in_expected in
  let msg =
    spf "it should find all reported findings and no more (%d errors)"
      num_errors
  in
  match num_errors with
  | 0 -> Stdlib.Ok ()
  | n -> Error (n, msg)

let compare_actual_to_expected_for_alcotest actual expected =
  match compare_actual_to_expected actual expected with
  | Ok () -> ()
  | Error (_num_errors, msg) -> Alcotest.fail msg
