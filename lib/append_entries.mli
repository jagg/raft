open! Base

type 'a t = {
  term                   : int;
  prev_log_index         : int;
  prev_log_term          : int;
  leader_commit_index    : int;
  leader_id              : State.Server_id.t;
  destination_id         : State.Server_id.t;
  entries                : 'a State.Persistent_state.entry list;
}
[@@deriving sexp]

type result = {
  success      : bool;
  current_term : int;
}
[@@deriving sexp]

(** [emit_all state] emits one AppendEntries request for each peer in [state]. *)
val emit_all : 'a State.t -> 'a t list

(** [apply operation state] applies an incoming AppendEntries [operation]
    to [state] and returns:
    - the new state
    - the list of log entries that need to be applied and commited in the state machine
    - the RPC [result] *)
val apply
  :  'a t
  -> 'a State.t
  -> 'a State.t * 'a State.Persistent_state.entry list * result
