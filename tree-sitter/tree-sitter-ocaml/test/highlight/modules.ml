module type T = sig
(* <- keyword *)
    (* ^ keyword *)
         (* ^ module *)
           (* ^ punctuation.delimiter *)
             (* ^ keyword *)
  val x : int
end
(* <- keyword *)

module M : T = struct
(* <- keyword *)
    (* ^ module *)
      (* ^ punctuation.delimiter *)
        (* ^ module *)
  let x = 0
end

module F (M : T) = struct
    (* ^ module *)
      (* ^ punctuation.bracket *)
       (* ^ module *)
           (* ^ module *)
            (* ^ punctuation.bracket *)
                (* ^ keyword *)
  include M
  (* <- keyword *)
       (* ^ module *)
end

module N = F (M)
    (* ^ module *)
        (* ^ module *)
           (* ^ module *)

let x = N.x
     (* ^ module *)
      (* ^ punctuation.delimiter *)
