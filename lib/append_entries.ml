open! Base

type 'a t = {
  term : int;
  prev_log_index : int;
  prev_log_term : int;
  leader_commit_index : int;
  leader_id : State.Server_id.t;
  destination_id : State.Server_id.t;
  entries : 'a State.Persistent_state.entry list;
}
[@@deriving sexp]

type result = {
  success : bool;
  current_term : int;
}
[@@deriving sexp]

(** Assumes a log, sorted in reverse order by index, and finds the first entry
    with the same or smaller index
*)
let rec go_to_index log index =
  let (current : 'a State.Persistent_state.entry option) = List.hd log in
  match current with
  | None -> []
  | Some entry -> if entry.index <= index then log
    else match List.tl log with
      | None -> []
      | Some lst -> go_to_index lst index

let term_at_index log index =
  match List.hd (go_to_index log index) with
  | None -> 0
  | Some entry -> entry.term

let emit (state : 'a State.t) (id : State.Server_id.t) =
  let follower_next_idx = Option.value ~default:(State.last_log_index state + 1) @@
    Map.find state.volatile.next_index id
  in
  let entries = if (State.last_log_index state) >= follower_next_idx then
    List.take_while state.persistent.log
      ~f:(fun entry -> entry.index >= follower_next_idx)
      else []
  in
  {
    term = state.persistent.current_term;
    prev_log_index = follower_next_idx - 1;
    prev_log_term = term_at_index state.persistent.log @@ follower_next_idx - 1;
    leader_commit_index = state.volatile.commit_index;
    leader_id = state.persistent.id;
    destination_id = id;
    entries;
  }

let emit_all (state : 'a State.t) =
  Map.fold state.volatile.next_index ~init:[]
    ~f:(fun ~key ~data:_ acc -> (emit state key)::acc)

let apply operation (state : 'a State.t) =
  let from_index = go_to_index state.persistent.log operation.prev_log_index in
  let outdated = operation.term < state.persistent.current_term in
  let term_match = match List.hd from_index with
    | None -> true (* If the follower log is empty we can just fill it
                      in, as long as the leader is not outdated *)
    | Some entry -> entry.term = operation.prev_log_term
  in
  let new_log =
  if not outdated && term_match then
    List.append  operation.entries from_index
  else state.persistent.log in
  let last_index = Option.map ~f:(fun entry -> entry.index) (List.hd new_log) in
  let last_index = Option.value ~default:state.volatile.commit_index last_index in
  let new_vote = if operation.term > state.persistent.current_term then
      None
    else
      state.persistent.voted_for
  in
  let new_state : 'a State.t = {
    volatile = {
      state.volatile with commit_index = Int.min
                              last_index
                              operation.leader_commit_index
    };
    persistent = {
      state.persistent with
      log = new_log;
      voted_for = new_vote;
      current_term = Int.max
          state.persistent.current_term
          operation.term
    }}
  in
  let ops_count = new_state.volatile.commit_index - state.volatile.commit_index in
  let ops_to_apply = List.rev @@ List.take new_state.persistent.log ops_count in
  (new_state,
   ops_to_apply,
   {
      success = not outdated && term_match;
      current_term = new_state.persistent.current_term;
    }) 
