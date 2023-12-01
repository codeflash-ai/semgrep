(* Yoann Padioleau
 *
 * Copyright (C) 2022 Semgrep Inc.
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

(*****************************************************************************)
(* Globals *)
(*****************************************************************************)

(** This global is used by the reporter to print the difference between
    the time the log call was done and the time the program was started.
    TODO? Actually, the implementation is a bit dumb and probably show weird
     metrics when we use [lwt]. For such case, it's better to add a _counter_
     and use the tag mechanism to really show right metrics.

     This variable is set when we configure loggers.
*)

(* in seconds *)
let time_program_start = ref 0.

let default_skip_libs =
  [
    "ca-certs";
    "bos";
    "cohttp.lwt.client";
    "cohttp.lwt.io";
    "conduit_lwt_server";
    "mirage-crypto-rng.lwt";
    "mirage-crypto-rng-lwt";
    "mirage-crypto-rng.unix";
    "handshake";
    "tls.config";
    "tls.tracing";
    "eio_linux";
    "x509";
  ]

(* used for testing *)
let in_mock_context = ref false

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

(* ANSI escape sequences for colored output, depending on log level *)
let color level =
  match level with
  | Logs.Warning -> Some "33" (*yellow*)
  | Logs.Error -> Some "31" (*red*)
  | _else -> None

(* print an ANSI escape sequence - not worth to use an extra library
   (such as ANSIterminal) for this *)
let pp_sgr ppf style =
  Format.pp_print_as ppf 0 "\027[";
  Format.pp_print_as ppf 0 style;
  Format.pp_print_as ppf 0 "m"

(* alt: use Mtime_clock.now () *)
let now () : float = UUnix.gettimeofday ()

(* log reporter *)
let reporter ?(with_timestamp = false) ?(dst = Fmt.stderr) () =
  let report _src level ~over k msgf =
    let pp_style, style, style_off =
      match color level with
      | None -> ((fun _ppf _style -> ()), "", "")
      | Some x -> (pp_sgr, x, "0")
    in
    let k _ =
      over ();
      k ()
    in
    let r =
      msgf @@ fun ?header ?tags:_ fmt ->
      if with_timestamp then
        let current = now () in
        UFormat.kfprintf k dst
          ("@[[%05.2f]%a: " ^^ fmt ^^ "@]@.")
          (current -. !time_program_start)
          Logs_fmt.pp_header (level, header)
      else UFormat.kfprintf k dst ("@[%a" ^^ fmt ^^ "@]@.") pp_style style
    in
    Format.fprintf dst "%a" pp_style style_off;
    r
  in
  { Logs.report }

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

(* Enable basic logging (level = Logs.Warning) so that you can use Logging
 * calls even before a precise call to setup_logging.
 *)
let enable_logging () =
  Logs.set_level ~all:true (Some Logs.Warning);
  Logs.set_reporter (reporter ());
  ()

let setup_logging ?(skip_libs = default_skip_libs) ~force_color ~level () =
  let style_renderer = if force_color then Some `Ansi_tty else None in
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level ~all:true level;
  let with_timestamp = level =*= Some Logs.Debug in
  time_program_start := now ();
  if not !in_mock_context then Logs.set_reporter (reporter ~with_timestamp ());
  (* from https://github.com/mirage/ocaml-cohttp#debugging *)
  (* Disable all third-party libs logs *)
  Logs.Src.list ()
  |> List.iter (fun src ->
         match Logs.Src.name src with
         | x when List.mem x skip_libs -> Logs.Src.set_level src None
         (* those are the one we are really interested in *)
         | "application" -> ()
         | s -> failwith ("Logs library not handled: " ^ s))

(*****************************************************************************)
(* TODO: remove those (see .mli) *)
(*****************************************************************************)

let err_tag ?(tag = " ERROR ") () =
  ANSITerminal.sprintf
    [ ANSITerminal.white; ANSITerminal.Bold; ANSITerminal.on_red ]
    "%s" tag

let warn_tag ?(tag = " WARN ") () =
  ANSITerminal.sprintf
    [ ANSITerminal.white; ANSITerminal.Bold; ANSITerminal.on_yellow ]
    "%s" tag

let success_tag ?(tag = " SUCCESS ") () =
  ANSITerminal.sprintf
    [ ANSITerminal.white; ANSITerminal.Bold; ANSITerminal.on_green ]
    "%s" tag