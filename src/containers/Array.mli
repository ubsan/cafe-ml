module Mutable = Base.Array

type +'a t

type unordered_error = Duplicate of int | Empty_cell of int

val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int

include Container.S1 with type 'a t := 'a t

val max_length : int

external get : 'a t -> int -> 'a = "%array_safe_get"

external unsafe_get : 'a t -> int -> 'a = "%array_unsafe_get"

val empty : unit -> 'a t

val create : len:int -> 'a -> 'a t

val init : int -> f:(int -> 'a) -> 'a t

val of_sequence : len:int -> 'a Sequence.t -> 'a t

val of_sequence_unordered :
  len:int -> (int * 'a) Sequence.t -> ('a t, unordered_error) Result.t

val to_sequence : 'a t -> 'a Sequence.t

val append : 'a t -> 'a t -> 'a t

val concat : 'a t list -> 'a t

val to_mutable : 'a t -> 'a Mutable.t

val to_mutable_inplace : 'a t -> 'a Mutable.t

val of_list : 'a list -> 'a t

val of_mutable : 'a Mutable.t -> 'a t

val of_mutable_inplace : 'a Mutable.t -> 'a t

val map : 'a t -> f:('a -> 'b) -> 'b t

val iteri : 'a t -> f:(int -> 'a -> unit) -> unit

val mapi : 'a t -> f:(int -> 'a -> 'b) -> 'b t

val foldi : 'a t -> init:'b -> f:(int -> 'b -> 'a -> 'b) -> 'b

val fold_right : 'a t -> f:('a -> 'b -> 'b) -> init:'b -> 'b

val findi : 'a t -> f:(int -> 'a -> bool) -> (int * 'a) option