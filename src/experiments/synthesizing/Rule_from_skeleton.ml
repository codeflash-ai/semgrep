open Common
module In = Input_to_core_j

type formula_json =
  | P of string
  | And of formula_json list
  | Or of formula_json list
  | Not of formula_json
  | Inside of formula_json

type rule_json = {
  id : string;
  match_ : Yojson.Safe.t;
  message : string;
  severity : string;
  languages : string list;
}
[@@deriving yojson]

let lang = Lang.Python

let rec formula_to_json formula : Yojson.Safe.t =
  match formula with
  | P str -> `String str
  | And xs -> `Assoc [ ("all", `List (List.map formula_to_json xs)) ]
  | Or xs -> `Assoc [ ("any", `List (List.map formula_to_json xs)) ]
  | Not x -> `Assoc [ ("not", formula_to_json x) ]
  | Inside x -> `Assoc [ ("inside", formula_to_json x) ]

let pattern_of_matches matches =
  match matches with
  | [] -> "empty"
  | xs -> (
      let config = Rule_options.default_config in
      let anys =
        List.map
          (fun p ->
            pr2 p;
            Parse_pattern.parse_pattern lang p)
          xs
      in
      let pattern = Pattern_from_Targets.generate_patterns config anys lang in
      match pattern with
      | None -> "none, crazy"
      | Some p ->
          pr2 (AST_generic.show_any p);
          Pretty_print_pattern.pattern_to_string lang p)

let rec skeleton_to_formula (skeleton : In.rule_skeleton) : formula_json =
  let { In.op; children; matches } = skeleton in
  let children = Option.fold ~none:[] ~some:(fun x -> x) children in
  let matches = Option.fold ~none:[] ~some:(fun x -> x) matches in
  match op with
  | In.And -> And (List.map skeleton_to_formula children)
  | In.Or -> Or (List.map skeleton_to_formula children)
  | In.XPat -> P (pattern_of_matches matches)
  | In.Negation ->
      let negated_val =
        match children with
        | [] -> P "none_delete_me"
        | x :: _xs -> skeleton_to_formula x
      in
      Not negated_val
  | In.Inside ->
      let inside_val =
        match children with
        | [] -> P "inside_delete_me"
        | x :: _xs -> skeleton_to_formula x
      in
      Inside inside_val
  | _ -> raise Common.Todo

let convert_skeleton_to_rule (skeleton : In.rule_skeleton) : rule_json =
  let match_ = skeleton_to_formula skeleton |> formula_to_json in
  {
    id = "autogenerated-rule-change-me";
    match_;
    message = "<Your message here>";
    severity = "WARNING";
    languages = [ "python" ];
  }

let generate_rule json =
  let rule_skeletons = read_file json |> In.rule_skeletons_of_string in
  match rule_skeletons with
  | [] -> failwith "No rule provided"
  | rule_skeleton :: _ ->
      let rule = convert_skeleton_to_rule rule_skeleton in
      let json_str =
        rule |> rule_json_to_yojson
        |> (fun r -> `Assoc [ ("rules", `List [ r ]) ])
        |> Yojson.Safe.to_string
        |> Str.global_replace (Str.regexp "match_") "match"
      in
      pr json_str
