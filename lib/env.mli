val make : ?filename:string -> ?arguments:string list ->
  ?input:in_channel -> ?output:out_channel ->
  ?error:out_channel -> unit -> Value.t
