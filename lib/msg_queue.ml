open! Base
open Eio.Std

type ('a, 'b) msg = Msg of ('a * ('b Promise.u)) 
      
type ('a, 'b) t =  ('a, 'b) msg Eio.Stream.t

let make sw handler =
  let stream = Eio.Stream.create 120 in
  let rec handle () =
    let msg = Eio.Stream.take stream in
    (match msg with
       Msg (body, resolver) ->
       let response = handler stream body in
       Promise.resolve resolver response);
    handle ()
  in
  Fiber.fork ~sw handle; 
  stream

let send queue body =
  let promise, resolver  = Promise.create () in
  Eio.Stream.add queue @@ Msg (body, resolver);
  (** We don't want to return until we know it's been committed *)
  traceln "Wating for a response...";
  let r = Promise.await promise in
  traceln "Response arrived";
  r
