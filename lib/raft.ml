open! Base
open Eio

module Command = struct
  type t =
    | Process_append of State_machine.update Append_entries.t
    | Process_vote of Request_vote.t
    | Execute of State_machine.update
    | Request_vote
    | Send_heartbeat
end
[@@deriving sexp]

module Response = struct
  type t =
    | Done
    | Error of string
    | Append_response of Append_entries.result
    | Election_response of Request_vote.result
end
[@@deriving sexp]

type t = {
  mutable state : State_machine.update State.t;
  (* queue : (Command.t, Response.t) Msg_queue.t; *)
  quorum : int;
  replicas : (string * int) Map.M(State.Server_id).t;
  mutable state_machine : State_machine.t;
  system_clock : float Time.clock_ty Std.r;
  mutable timer : Switch.t option; 
}

let init_cluster_map replicas =
  Map.keys replicas
  |> List.fold ~init:(Map.empty (module State.Server_id))
                 ~f:(fun acc id -> Map.set acc ~key:id ~data:0)


let trigger_election raft sw net =
  traceln "Triggering election";
  let (new_state, msg) = Request_vote.emit raft.state in
  raft.state <- new_state;
  let responses = List.map (Map.data raft.replicas) ~f:(fun (ip,port) ->
      (* TODO run this in parallel! *)
      Api.send_vote_request sw net msg ip port)
  in
  let ok_resp = List.filter_map responses ~f:(fun r -> match r with
      | Ok r -> Some r
      | Error e ->
        traceln "Trigger election error: %s" (Error.to_string_hum e);
        None)
  in
  let vote_count = List.fold ok_resp ~init:0 ~f:(fun acc resp ->
      acc + (if resp.vote_granted then 1 else 0))
  in 
  let latest_term = List.fold ok_resp ~init:0 ~f:(fun acc resp ->
      Int.max acc resp.current_term)
  in 
  let new_state : State_machine.update State.t = {
    persistent = { raft.state.persistent with
                   current_term = Int.max latest_term raft.state.persistent.current_term
                 };
    volatile = { raft.state.volatile with
                 mode = if vote_count >= List.length responses then Leader else Follower
               };
  } in
  let st = State.sexp_of_t [%sexp_of: State_machine.update] new_state in
  traceln "New State:\n %s" @@ Sexp.to_string_hum st;
  raft.state <- new_state

let send_heartbeat raft sw net =
  traceln "Sending heartbeats";
  let msgs = Append_entries.emit_all raft.state in
  let responses = List.map msgs ~f:(fun msg ->
      (* TODO run this in parallel! *)
      match Map.find raft.replicas msg.destination_id with
      | Some (ip, port) ->
        traceln "Sending heartbeat to %s:%d" ip port;
        Some (Api.send_append sw net msg ip port);
      | None ->
        traceln "Failed to send heartbeat, I don't know the id";
        None
    )
  in
  let latest_term = List.fold responses ~init:0 ~f:(fun acc resp ->
      let term = Option.map resp ~f:(fun r ->
          match r with
          | Ok r -> r.current_term
          | Error e ->
            traceln "Failed to send heartbeat: %s" (Error.to_string_hum e);
            0
        ) in
      Int.max acc (Option.value term ~default:0))
  in 
  let success_count = List.fold responses ~init:0 ~f:(fun acc resp ->
      let v = match resp with
        | Some r ->
          (match r with
           |  Ok r -> if r.success then 1 else 0
           |  Error _ -> 0) 
        | None -> 0
      in
      acc + v)
  in
  let commit = success_count >= raft.quorum in
  let new_state : State_machine.update State.t = {
    persistent = { raft.state.persistent with
                   current_term = Int.max latest_term raft.state.persistent.current_term
                 };
    volatile = { raft.state.volatile with
                 mode = if latest_term > raft.state.persistent.current_term then Follower else Leader;
                 commit_index = if commit then State.last_log_index raft.state else raft.state.volatile.commit_index;
               };
  } in
  raft.state <- new_state

let rec reset_timer raft net (queue : (Command.t, Response.t) Msg_queue.t) =
  traceln "Resetting timer";
  Option.iter raft.timer ~f:(fun sw ->
      Eio.Switch.fail sw (Cancel.Cancelled Stdlib.Exit));
  Eio.Switch.run_protected ~name:"Clock" @@ fun sw ->
  raft.timer <- Some sw;
  Fiber.fork ~sw (fun () ->
      let secs = match raft.state.volatile.mode with
        | Leader -> 200.0 /. 1000.0;
        | Follower -> 3000.0 /. 1000.0;
        | Candidate -> 3000.0 /. 1000.0;
      in
      let wait_for = secs +. Random.float secs in
      traceln "Sleep for %.3f" wait_for;
      Eio.Time.sleep raft.system_clock wait_for;
      (* Trigger election and reset timer *)
      traceln "Waking up";
      let _ = match raft.state.volatile.mode with
        | Leader ->
          traceln "I'm a leader!";
          Msg_queue.send queue Command.Send_heartbeat
        | Follower ->
          traceln "I'm a follower!";
          Msg_queue.send queue Command.Request_vote
        | Candidate ->
          traceln "I'm a candidate!";
          Msg_queue.send queue Command.Request_vote
      in
      reset_timer raft net queue
    )

let process_update raft update =
  let sm = State_machine.update raft.state_machine update in
  raft.state_machine <- sm

let append_entries raft queue msg net =
  let (new_state, entries, result) = Append_entries.apply msg raft.state in
  raft.state <- new_state;
  if result.success then
    reset_timer raft net queue;
  List.iter entries ~f:(fun entry ->
      process_update raft entry.command;
      raft.state <- State.inc_last_applied raft.state;
    );
  result


let process_vote_request raft (queue : (Command.t, Response.t) Msg_queue.t) msg net =
  let (new_state, result) = Request_vote.apply msg raft.state in
  raft.state <- new_state;
  if result.vote_granted then
    (traceln "Voted for you!";
    reset_timer raft net queue;)
  else
    traceln "Didn't get my vote";
  result

let handler raft net sw (queue : (Command.t, Response.t) Msg_queue.t) (command : Command.t) =
  match command with
    | Process_append msg -> Response.Append_response (append_entries raft queue msg net);
    | Process_vote msg -> Response.Election_response (process_vote_request raft queue msg net);
    | Send_heartbeat -> send_heartbeat raft sw net; Response.Done
    | Request_vote -> trigger_election raft sw net; Response.Done
    | Execute update ->
      match raft.state.volatile.mode with
      | Leader -> process_update raft update; Response.Done
      | Follower | Candidate -> Response.Error "I'm not the leader"


let make sw id net env replicas =
  let (persistent : State_machine.update State.Persistent_state.t) = {
    current_term = 0;
    voted_for = None;
    log = [];
    id = Id id;
  } in
  let (volatile : State.Volatile_state.t) = {
    mode = Follower;
    commit_index = 0;
    last_applied = 0;
    next_index = init_cluster_map replicas;
    match_index = init_cluster_map replicas;
  } in
  let (state : State_machine.update State.t) = {
    persistent;
    volatile;
  } in
  let raft =
  {
    state;
    replicas;
    state_machine = State_machine.make;
    timer = None;
    system_clock = Eio.Stdenv.clock env;
    quorum = Map.length replicas / 2
  }
  in
  let queue = Msg_queue.make sw  (handler raft net sw) in
  (raft, queue)
