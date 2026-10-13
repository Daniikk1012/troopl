val default : Value.t
val make : ?filename:string -> ?input:in_channel -> ?output:out_channel ->
  ?error:out_channel -> unit -> Value.t
