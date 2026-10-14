(** Decode complete scalar values; leave a valid unfinished suffix untouched. *)
type decoded = {
  text : string;
  consumed : int;
  invalid : (int * int * string) option;
}

let decode ~size ~get =
  let buffer = Buffer.create (min size 4096) in
  let result consumed invalid =
    { text = Buffer.contents buffer; consumed; invalid }
  in
  let invalid i byte = result i (Some (i, byte, "invalid UTF-8 byte")) in
  let rec loop i =
    if i = size then result i None else
      let first = get i in
      if first >= 0 && first <= 0x7f then (
        Buffer.add_char buffer (Char.chr first);
        loop (i + 1))
      else
        let shape =
          if first >= 0xc2 && first <= 0xdf then Some (2, 0x80, 0xbf)
          else if first = 0xe0 then Some (3, 0xa0, 0xbf)
          else if first >= 0xe1 && first <= 0xec then Some (3, 0x80, 0xbf)
          else if first = 0xed then Some (3, 0x80, 0x9f)
          else if first >= 0xee && first <= 0xef then Some (3, 0x80, 0xbf)
          else if first = 0xf0 then Some (4, 0x90, 0xbf)
          else if first >= 0xf1 && first <= 0xf3 then Some (4, 0x80, 0xbf)
          else if first = 0xf4 then Some (4, 0x80, 0x8f)
          else None
        in
        match shape with
        | None -> invalid i first
        | Some (count, low, high) ->
            let rec continuation j bytes =
              if j = count then (
                List.rev bytes
                |> List.iter (fun byte ->
                  Buffer.add_char buffer (Char.chr byte));
                loop (i + count))
              else if i + j = size then result i None
              else
                let byte = get (i + j) in
                let lower, upper = if j = 1 then low, high else 0x80, 0xbf in
                if byte < lower || byte > upper then invalid (i + j) byte
                else continuation (j + 1) (byte :: bytes)
            in
            continuation 1 [first]
  in
  loop 0
