let t = true
     (* ^ constant *)

let c = 'c'
     (* ^ string *)

let () = Printf.printf "string\n%d" 5
 (* ^ punctuation.bracket *)
                    (* ^ string *)
                           (* ^ escape *)
                             (* ^ string.special *)
                                 (* ^ number *)
 let x = {id|string|id}
      (* ^ string *)

let f = function +1 -> true | - 1 -> false
              (* ^ number *)
                           (* ^ number *)
