type t = { kind : kind; pos : Position.t }

and kind =
  | Definition          of { name : string; value : t; scope : t }
  | RecursiveDefinition of { name : string; entries : entry list; scope : t }
  | Sequence            of t * t
  | Object              of entry list
  | Variable            of string
  | Number              of float
  | String              of string
  | Environment
  | Call                of { value : t; name : string; args : t list }

and entry = { kind : entry_kind; pos : Position.t }

and entry_kind = Method    of { name : string; args : string list; body : t }
               | Inclusion of t


let rec to_string expr =
  Position.to_string expr.pos ^ ": " ^ string_of_kind expr.kind

and string_of_kind = function
  | Definition { name; value; scope } ->
      "Definition " ^ name ^ " = (" ^ to_string value ^ ") in ("
      ^ to_string scope ^ ")"
  | RecursiveDefinition { name; entries; scope } ->
      "RecursiveDefinition " ^ name ^ " = ["
      ^ String.concat "; " (List.map string_of_entry entries) ^ "] in ("
      ^ to_string scope ^ ")"
  | Sequence (a, b) -> "Sequence (" ^ to_string a ^ ") (" ^ to_string b ^ ")"
  | Object entries ->
      "Object [" ^ String.concat "; " (List.map string_of_entry entries) ^ "]"
  | Variable name -> "Variable " ^ name
  | Number value -> "Number " ^ string_of_float value
  | String value -> "String \"" ^ String.escaped value ^ "\""
  | Environment -> "Environment"
  | Call { value; name; args } ->
      "Call (" ^ to_string value ^ ") " ^ name
      ^ String.concat "" (List.map (fun e -> " (" ^ to_string e ^ ")") args)

and string_of_entry entry =
  Position.to_string entry.pos ^ ": " ^ string_of_entry_kind entry.kind

and string_of_entry_kind = function
  | Method { name; args; body } ->
      "Method " ^ name
      ^ String.concat "" (List.map (fun s -> s ^ " ") args) ^ " = ("
      ^ to_string body ^ ")"
  | Inclusion expr -> "Inclusion (" ^ to_string expr ^ ")"
