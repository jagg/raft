open! Base

module Server_id : sig
  (** The identity of a single Raft server. *)
  type t = Id of string
  [@@deriving compare, sexp]

  (** The comparator and comparator witness that let you use [t] as a key in
      Base’s maps and sets. *)
  include Comparator.S with type t := t
end

module Persistent_state : sig
  type 'a entry = {
    term : int;
    index : int;
    command : 'a;
  }
  [@@deriving sexp]

  type 'a t = {
    (** Highest term server has seen *)
    current_term : int;

    (** Candidate that received vote in current term, if any *)
    voted_for : Server_id.t option;

    (** Log of all entries, newest first *)
    log : 'a entry list;

    (** This server’s own id *)
    id : Server_id.t;
  }
  [@@deriving sexp]
end

module Volatile_state : sig

  type mode =
    | Leader
    | Follower
    | Candidate
  [@@deriving sexp]

  type t = {
    mode : mode;
    commit_index : int;
    last_applied : int;

    (** For leaders: next log index to send to each follower *)
    next_index : int Map.M(Server_id).t;

    (** For leaders: highest log index known replicated on each follower *)
    match_index : int Map.M(Server_id).t;
  }
  [@@deriving sexp]
end

(** The overall Raft state, parameterized by the type of commands in the log *)
type 'a t = {
  persistent : 'a Persistent_state.t;
  volatile : Volatile_state.t;
}
[@@deriving sexp]

(** [last_log_index state] gives the index of the most‐recent log entry (0 if none). *)
val last_log_index : 'a t -> int

(** [last_log_term state] gives the term of the most‐recent log entry (0 if none). *)
val last_log_term  : 'a t -> int

(** [inc_last_applied state] increments [state.volatile.last_applied] by one. *)
val inc_last_applied : 'a t -> 'a t

(** [append_to_log state cmd] appends a new entry with current_term and next index to the head of the log. *)
val append_to_log   : 'a t -> 'a -> 'a t
