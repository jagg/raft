open! Core 
open Eio.Std

module Config = struct
  type operation = 
    | Add of string * int
    | Delete of string
    | Get of string
  [@@deriving sexp]

  type t = {
    operation: operation;
    host: string;
    port: int;
  }
  [@@deriving sexp]

  let default_config = {
    operation = Get "default";
    host = "127.0.0.1";
    port = 7771;
  }

  let parse () = 
    let host = ref default_config.host in
    let port = ref default_config.port in

    let anon_args = ref [] in
    let anon_fun arg = anon_args := arg :: !anon_args in

    let speclist = [
      ("-h", Stdlib.Arg.Set_string host, " Server hostname (default: 127.0.0.1)");
      ("-p", Stdlib.Arg.Set_int port, " Server port (default: 7771)");
    ] in

    let usage_msg = "Usage: raft_client [add|delete|get] <key> [value] -h <host> -p <port>" in
    Stdlib.Arg.parse speclist anon_fun usage_msg;

    let args = List.rev !anon_args in
    
    let parsed_operation = match args with
      | "add" :: key :: value :: [] ->
        (try Add (key, Int.of_string value)
         with _ -> failwith ("Invalid value: " ^ value ^ ". Must be an integer."))
      | "delete" :: key :: [] ->
        Delete key
      | "get" :: key :: [] ->
        Get key
      | [] ->
        Printf.printf "%s\n" usage_msg;
        Printf.printf "Commands:\n";
        Printf.printf "  add <key> <value>  - Add a key-value pair\n";
        Printf.printf "  delete <key>       - Delete a key\n";
        Printf.printf "  get <key>          - Get value for a key\n";
        Printf.printf "Options:\n";
        Printf.printf "  -h <host>          - Server hostname (default: 127.0.0.1)\n";
        Printf.printf "  -p <port>          - Server port (default: 7771)\n";
        exit 1
      | _ ->
        Printf.printf "Invalid arguments\n";
        Printf.printf "%s\n" usage_msg;
        exit 1
    in

    {
      operation = parsed_operation;
      host = !host;
      port = !port;
    }
end

let execute_operation config =
  Eio_main.run @@ fun env ->
  Switch.run ~name:"Client" @@ fun sw ->
  let net = Eio.Stdenv.net env in
  match config.Config.operation with
  | Add (key, value) ->
    (match Raft_lib.Api.send_client_add sw net key value config.host config.port with
     | Ok result -> 
       (match result with
        | Ok msg -> Printf.printf "Success: %s\n" msg
        | Error err -> Printf.printf "Error: %s\n" err)
     | Error err -> Printf.printf "Connection error: %s\n" (Error.to_string_hum err))
  
  | Delete key ->
    (match Raft_lib.Api.send_client_delete sw net key config.host config.port with
     | Ok result -> 
       (match result with
        | Ok msg -> Printf.printf "Success: %s\n" msg
        | Error err -> Printf.printf "Error: %s\n" err)
     | Error err -> Printf.printf "Connection error: %s\n" (Error.to_string_hum err))
  
  | Get key ->
    (match Raft_lib.Api.send_client_get sw net key config.host config.port with
     | Ok result -> 
       (match result with
        | Ok (Some value) -> Printf.printf "Key '%s' = %d\n" key value
        | Ok None -> Printf.printf "Key '%s' not found\n" key
        | Error err -> Printf.printf "Error: %s\n" err)
     | Error err -> Printf.printf "Connection error: %s\n" (Error.to_string_hum err))

let () =
  let config = Config.parse () in
  execute_operation config