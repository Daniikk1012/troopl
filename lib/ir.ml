type capture = { outer : int; inner : int }
type location = Local of int | Capture of int
type capture_plan = NoCaptures | ReuseCaptures | CaptureValues of location array

type t =
  | Definition          of { index : int; value : t; scope : t }
  | RecursiveDefinition of { index : int; entries : entry list; scope : t }
  | Sequence            of t * t
  | Object              of entry list
  | Variable            of int
  | Captured            of int
  | Number              of float * Position.t
  | String              of string * Position.t
  | Environment
  | Call of { value : t; name : string; selector : Selector.t;
              args : t list; pos : Position.t }

and entry =
  | CompiledMethod of {
      selector : Selector.t;
      args : int option list;
      body : t;
      plan : capture_plan;
      scope_size : int;
    }
  | Method of {
      name       : string;
      args       : int option list;
      body       : t;
      captures   : capture list;
      scope_size : int;
    }
  | Inclusion of { value : t; pos : Position.t }

let string_of_capture capture =
  string_of_int capture.outer ^ " -> " ^ string_of_int capture.inner

let rec to_string = function
  | Definition { index; value; scope } ->
      "Definition " ^ string_of_int index ^ " = (" ^ to_string value ^ ") in ("
      ^ to_string scope ^ ")"
  | RecursiveDefinition { index; entries; scope } ->
      "RecursiveDefinition " ^ string_of_int index ^ " = ["
      ^ String.concat "; " (List.map string_of_entry entries) ^ "] in ("
      ^ to_string scope ^ ")"
  | Sequence (a, b) -> "Sequence (" ^ to_string a ^ ") (" ^ to_string b ^ ")"
  | Object entries ->
      "Object [" ^ String.concat "; " (List.map string_of_entry entries) ^ "]"
  | Variable i -> "Variable " ^ string_of_int i
  | Captured i -> "Captured " ^ string_of_int i
  | Number (n, pos) ->
      "Number " ^ string_of_float n ^ " at " ^ Position.to_string pos
  | String (s, pos) ->
      "String \"" ^ String.escaped s ^ "\" at " ^ Position.to_string pos
  | Environment -> "Environment"
  | Call { value; name; args; pos; _ } ->
      "Call (" ^ to_string value ^ ") " ^ name
      ^ String.concat "" (List.map (fun x -> " (" ^ to_string x ^ ")") args)
      ^ " at " ^ Position.to_string pos

and string_of_entry = function
  | CompiledMethod { selector; body; plan; scope_size; _ } ->
      let plan = match plan with
        | NoCaptures -> "none"
        | ReuseCaptures -> "reuse"
        | CaptureValues sources -> "gather:" ^ string_of_int (Array.length sources)
      in
      "CompiledMethod " ^ Selector.describe selector ^ " " ^ plan
      ^ " locals:" ^ string_of_int scope_size ^ " " ^ to_string body
  | Method { name; args; body; captures; scope_size } ->
      "Method " ^ name ^ " ["
      ^ String.concat "; "
          (List.map
            (fun o -> Option.map string_of_int o |> Option.value ~default:"-")
            args)
      ^ "] = (" ^ to_string body ^ ") capturing ["
      ^ String.concat "; " (List.map string_of_capture captures)
      ^ "] scope_size = " ^ string_of_int scope_size
  | Inclusion { value; pos } ->
      "Inclusion (" ^ to_string value ^ ") at " ^ Position.to_string pos
