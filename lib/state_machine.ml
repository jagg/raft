open! Base

type update =
  | Set of string * int
  | Delete of string 
[@@deriving sexp]

type t = int Map.M(String).t

let make = Map.empty (module String)

let update machine op =
  match op with
  | Set (key, data) -> Map.set machine ~key ~data
  | Delete key -> Map.remove machine key

let get machine key =
  Map.find machine key
