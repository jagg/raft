open! Base

type t = {
  term : int;
  candidate_id : State.Server_id.t;
  last_log_index : int;
  last_log_term : int;
}
[@@deriving sexp]

type result = {
  current_term : int;
  vote_granted : bool;
}
[@@deriving sexp]

let emit (state : 'a State.t) =
  let msg = {
    term = state.persistent.current_term;
    candidate_id = state.persistent.id;
    last_log_index = State.last_log_index state;
    last_log_term = State.last_log_term state;
  }
  in
  let new_state : 'a State.t =
    {
      volatile = {
        state.volatile with
        mode = Candidate
      };
      persistent = {
        state.persistent with
        voted_for = Some state.persistent.id;
        current_term = state.persistent.current_term + 1;
      };
    }
  in
  (new_state, msg)


let apply operation (state : 'a State.t) =
  let outdated = operation.term < state.persistent.current_term in
  let voted_someone_else = match state.persistent.voted_for with
    | None -> false
    | Some id -> State.Server_id.compare id operation.candidate_id = 0
  in
  let candidate_up_to_date =
    if operation.last_log_term = (State.last_log_term state) then
      operation.last_log_index >= (State.last_log_index state)
    else
      operation.last_log_term > (State.last_log_term state)
  in
  let current_term = Int.max operation.last_log_term state.persistent.current_term in
  if not outdated && candidate_up_to_date && not voted_someone_else then
    (
      {
        state with
        persistent = { state.persistent with
                       voted_for = Some operation.candidate_id;
                       current_term;
                     };
      },
      {
        current_term;
        vote_granted = true;
      }
    )
  else
    (state, {
        current_term;
        vote_granted = false;
      })
