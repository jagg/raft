open! Base

(** RequestVote RPC request, parameterized by the type of commands in the log. *)
type t = {
  term            : int;
  candidate_id    : State.Server_id.t;
  last_log_index  : int;
  last_log_term   : int;
}
[@@deriving sexp]

(** RequestVote RPC response. *)
type result = {
  current_term : int;
  vote_granted : bool;
}
[@@deriving sexp]

(** [emit state] transitions [state] (of any command type) into Candidate,
    increments its term, records its own vote, and returns the new state
    plus the RequestVote message. *)
val emit : 'a State.t -> 'a State.t * t

(** [apply operation state] applies an incoming RequestVote [operation]
    to [state] (of any command type), returning:
    - the updated state (possibly recording the vote and/or updating [current_term])
    - the RequestVote [result] indicating whether the vote was granted *)
val apply : t -> 'a State.t -> 'a State.t * result
