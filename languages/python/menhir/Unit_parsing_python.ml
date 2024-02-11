let t = Testo.create

(*****************************************************************************)
(* Unit tests *)
(*****************************************************************************)

(* ran from the root of the semgrep repository *)
let tests_path = "tests"

let tests =
  Testo.categorize "parsing_python"
    [
      t "regression files" (fun () ->
          let dir = Filename.concat tests_path "python/parsing" in
          let files = Common2.glob (Filename.concat dir "*.py") in
          files
          |> List.iter (fun file ->
                 Testutil.run file (fun () ->
                     Parse_python.parse_program file |> ignore)));
    ]
