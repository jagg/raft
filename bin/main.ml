open! Core 
open Eio.Std

module Config = struct

  type cluster_config = {
    replicas : (string * int) Map.M(Raft_lib.State.Server_id).t;
    quorum : int
  }
  [@@deriving sexp]


  type t = {
    id: string;
    port : int;
    op_port : int;
    cluster : cluster_config;
  }
  [@@deriving sexp]

  let default_config = {
    id = "id";
    port = 12342;
    op_port = 12343;
    cluster =
        {
          replicas = Map.singleton (module Raft_lib.State.Server_id) (Id "one") ("127.0.0.1", 12343);
          quorum = 1;
        }
  }

  let load_cluster_config (file : string) : cluster_config =
    let sexp = Sexp.load_sexp file in
    cluster_config_of_sexp sexp

  let parse () = 

    let id = ref default_config.id in
    let port = ref default_config.port in
    let op_port = ref default_config.op_port in
    let cluster_config = ref "./cluster.conf" in

    let speclist = [
      ("-i", Stdlib.Arg.Set_string id, "Server Id");
      ("-p", Stdlib.Arg.Set_int port, "Input  port");
      ("-o", Stdlib.Arg.Set_int op_port, "Operations port");
      ("-f", Stdlib.Arg.Set_string cluster_config, "Path to cluster configuration")
    ] in

    let usage_msg = "Usage: server.exe -port 12342" in
    Stdlib.Arg.parse speclist (fun _ -> ()) usage_msg;
    {
      id = !id;
      cluster = load_cluster_config !cluster_config;
      port = !port;
      op_port = !op_port;
    }
end

let () =
  traceln "[SERVER] Starting Server";
  let config = Config.parse () in
  Eio_main.run @@ fun env ->
  Switch.run ~name:"Server" @@ fun sw ->
  let config_str = Config.sexp_of_t config in
  traceln "Server Config:\n %s" @@ Sexp.to_string_hum config_str;
  let raft = Raft_lib.Raft.make config.id env config.cluster.replicas in
  Raft_lib.Raft.start raft env sw config.op_port;
  traceln "[SERVER] Server ready!";

