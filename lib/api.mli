open! Base

type rpc =
  | Append of State_machine.update Append_entries.t
  | Request_vote of Request_vote.t
[@@deriving sexp]

type response =
  | Append_response of Append_entries.result
  | Request_vote_response of Request_vote.result
[@@deriving sexp]

(** Send an append msg to the replica on the specified IP and Port **)
val send_append : Eio.Switch.t ->
  [> [> `Generic ] Eio.Net.ty ] Eio_unix.source ->
  State_machine.update Append_entries.t ->
  string ->
  int ->
  Append_entries.result Or_error.t

(** Send a vote request msg to the replica on the specified IP and Port **)
val send_vote_request : Eio.Switch.t ->
  [> [> `Generic ] Eio.Net.ty ] Eio_unix.source ->
  Request_vote.t ->
  string ->
  int ->
  Request_vote.result Or_error.t

val send_response : response -> Eio.Buf_write.t -> unit

val receive_rpc_command : Eio.Buf_read.t -> rpc
