type t = { map : (string, int * Position.t) Hashtbl.t; mutable index : int }

type lowered = { ir : Ir.t; scope_size : int }

exception Error of string * Position.t

let create () = { map = Hashtbl.create 12; index = 0 }

let get_var lowerer name pos =
  match Hashtbl.find_opt lowerer.map name with
  | Some (i, _) -> i
  | None ->
      let i = lowerer.index in
      Hashtbl.add lowerer.map name (i, pos);
      lowerer.index <- i + 1;
      i

let rec lower_expr lowerer (expr : Expression.t) =
  match expr.kind with
  | Definition { name; value; scope } -> (
      let value = lower_expr lowerer value in
      let old = Hashtbl.find_opt lowerer.map name in
      Hashtbl.remove lowerer.map name;
      let scope = lower_expr lowerer scope in
      let ir : Ir.t =
        match Hashtbl.find_opt lowerer.map name with
        | Some (index, _) -> Definition { index; value; scope }
        | None            -> Sequence (value, scope)
      in
      Hashtbl.remove lowerer.map name;
      Option.iter (Hashtbl.add lowerer.map name) old;
      ir)
  | RecursiveDefinition { name; entries; scope } -> (
      let old = Hashtbl.find_opt lowerer.map name in
      Hashtbl.remove lowerer.map name;
      let entries = List.map (lower_entry lowerer) entries in
      let scope = lower_expr lowerer scope in
      let ir : Ir.t =
        match Hashtbl.find_opt lowerer.map name with
        | Some (index, _) -> RecursiveDefinition { index; entries; scope }
        | None            -> Sequence (Object entries, scope)
      in
      Hashtbl.remove lowerer.map name;
      Option.iter (Hashtbl.add lowerer.map name) old;
      ir)
  | Sequence (a, b) ->
      let a = lower_expr lowerer a in
      let b = lower_expr lowerer b in
      Sequence (a, b)
  | Object entries -> Object (List.map (lower_entry lowerer) entries)
  | Variable v -> Variable (get_var lowerer v expr.pos)
  | Number n -> Number n
  | String s -> String s
  | Environment -> Environment
  | Call { value; name; args } ->
      let value = lower_expr lowerer value in
      let args  = List.map (lower_expr lowerer) args in
      Call { value; name; args; pos = expr.pos }

and lower_entry lowerer entry =
  match entry.kind with
  | Method { name; args; body } ->
      let indices = Hashtbl.create 12 in
      List.iteri
        (fun i s ->
          if Hashtbl.mem indices s then
            raise (Error
              ("duplicate argument names in method definition", entry.pos))
          else
            Hashtbl.add indices s i)
        args;
      let lowerer' = create () in
      let body = lower_expr lowerer' body in
      let args = Array.make (List.length args) None in
      let captures =
        Hashtbl.to_seq lowerer'.map
        |> Seq.filter_map (fun (s, (i, p)) : Ir.capture option ->
             match Hashtbl.find_opt indices s with
             | Some i' -> args.(i') <- Some i; None
             | None -> Some { outer = get_var lowerer s p; inner = i })
        |> List.of_seq
      in
      let args = Array.to_list args in
      Method { name; args; body; captures; scope_size = lowerer'.index }
  | Inclusion value ->
      Inclusion { value = lower_expr lowerer value; pos = entry.pos }

let lower expr =
  let lowerer = create () in
  let ir = lower_expr lowerer expr in
  Hashtbl.iter
    (fun s (i, p) -> raise (Error ("unknown variable \"" ^ s ^ "\"", p)))
    lowerer.map;
  { ir; scope_size = lowerer.index }
