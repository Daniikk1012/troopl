(** Opt-in proposal capabilities; the default v0.2 environment is unchanged. *)
let extend env = Meta.extend env |> Symbols.extend
