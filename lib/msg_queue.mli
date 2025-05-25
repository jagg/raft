open! Base
open Eio.Std

(** A msg with body of type 'a and will produce responses of type 'b *)
type ('a, 'b) msg = Msg of ('a * ('b Promise.u)) 
      
(** A queue that receives msgs of type 'a and returns responses of type 'b *)
type ('a, 'b) t =  ('a, 'b) msg Eio.Stream.t

val make : Switch.t ->
  (('a, 'b) msg Eio.Stream.t -> 'a -> 'b) ->
  ('a, 'b) msg Eio.Stream.t


(** Send the body of type 'a that will be processed by the handler of
    the queue, returning a response of type 'b *)
val send : ('a, 'b) msg Eio.Stream.t -> 'a -> 'b
