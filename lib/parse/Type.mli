include module type of struct include Types.Type end

val mutability_equal : mutability -> mutability -> bool

val mutability_to_string : mutability -> lang:Lang.t -> string

val to_string : _ t -> lang:Lang.t -> string

module Data : sig
  include module type of struct include Types.Type_Data end

  val to_string : ?name:string -> t -> lang:Lang.t -> string
end

module Definition = Types.Type_Definition
