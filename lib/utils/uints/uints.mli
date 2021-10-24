module Uint8 : sig
  include Uints_intf.S
  val of_char : char -> t
  val to_char : t -> char
end

module Uint16 : sig
  include Uints_intf.S
  val of_uint8 : Uint8.t -> t
  val to_uint8 : t -> Uint8.t
end

(* TODO: Properly implement Int8 *)
module Int8 : sig
  type t [@@deriving show]
  val of_byte : Uint8.t -> t
  val of_int : int -> t
  val to_int : t -> int
  val is_neg : t -> bool
  val abs : t -> t
end

type uint8 = Uint8.t [@@deriving show]

type uint16 = Uint16.t [@@deriving show]

type int8 = Int8.t [@@deriving show]
