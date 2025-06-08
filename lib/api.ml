open! Base

type rpc =
  | Append of State_machine.update Append_entries.t
  | Request_vote of Request_vote.t
  | Client_add of string * int
  | Client_delete of string
  | Client_get of string
[@@deriving sexp]

type response =
  | Append_response of Append_entries.result
  | Request_vote_response of Request_vote.result
  | Client_response of (string, string) Result.t
  | Client_get_response of (int option, string) Result.t
[@@deriving sexp]

let encode_string pos buffer str =
  let len = String.length str in
  Stdlib.BytesLabels.blit_string ~src: str ~src_pos:0 ~dst: buffer ~dst_pos: pos ~len

let encode_int32 pos buffer int =
  Stdlib.Bytes.set_int32_be buffer pos int

let push_str_exn pos buffer str =
  let len = String.length str in
  let len32 = Int32.of_int_exn len in
  encode_int32 pos buffer len32;
  encode_string (pos + 4) buffer str;
  pos + 4 + len

let get_sexp of_sexp reader =
  let len = Bytes.of_string @@ Eio.Buf_read.take 4 reader in
  let len = Int.of_int32_exn (Stdlib.Bytes.get_int32_be len 0) in
  let msg = Eio.Buf_read.take len reader in
  let sexp = Parsexp.Single.parse_string_exn msg in
  of_sexp sexp

let send_sexp of_sexp objs writer =
  let sexp = of_sexp objs in
  let sexp = Sexplib.Sexp.to_string sexp in
  let len = String.length sexp in
  let buffer = Bytes.create (len + 4) in
  (** Not sure if there is a way to write into the socket without allocating buffers *)
  let _ = push_str_exn 0 buffer sexp in
  Eio.Buf_write.bytes writer buffer

let send_response response writer =
  send_sexp [%sexp_of: response] response writer 

let send_rpc
    ~(sexp_of_req : 'a -> Sexp.t)
    ~(of_sexp_resp : Sexp.t -> 'b)
    sw net
    (req : 'a)
    ip port
  : 'b =
  let ipp   = Unix.inet_addr_of_string ip in
  let ipv4  = Eio_unix.Net.Ipaddr.of_unix ipp in
  let addr  = `Tcp (ipv4, port) in
  let flow  = Eio.Net.connect ~sw net addr in
  let reader = Eio.Buf_read.of_flow flow ~max_size:4096 in
  Eio.Buf_write.with_flow flow @@ fun writer ->
    send_sexp sexp_of_req req writer;
    get_sexp of_sexp_resp reader

let send_append sw net msg ip port =
  Or_error.try_with @@ fun () ->
   match send_rpc
     ~sexp_of_req:[%sexp_of: rpc]
     ~of_sexp_resp:[%of_sexp: response]
     sw net (Append msg) ip port
    with
    | Append_response msg -> msg
    | Request_vote_response _ -> failwith "Wrong response"
    | Client_response _ -> failwith "Wrong response"
    | Client_get_response _ -> failwith "Wrong response"
  

let send_vote_request sw net msg ip port =
  Or_error.try_with @@ fun () ->
  match send_rpc
    ~sexp_of_req:[%sexp_of: rpc]
    ~of_sexp_resp:[%of_sexp: response]
    sw net (Request_vote msg) ip port
  with
   | Append_response _ -> failwith "Wrong response"
   | Request_vote_response msg -> msg 
   | Client_response _ -> failwith "Wrong response"
   | Client_get_response _ -> failwith "Wrong response"
  

let send_client_add sw net key value ip port =
  Or_error.try_with @@ fun () ->
  match send_rpc
    ~sexp_of_req:[%sexp_of: rpc]
    ~of_sexp_resp:[%of_sexp: response]
    sw net (Client_add (key, value)) ip port
  with
   | Append_response _ -> failwith "Wrong response"
   | Request_vote_response _ -> failwith "Wrong response"
   | Client_response result -> result
   | Client_get_response _ -> failwith "Wrong response"

let send_client_get sw net key ip port =
  Or_error.try_with @@ fun () ->
  match send_rpc
    ~sexp_of_req:[%sexp_of: rpc]
    ~of_sexp_resp:[%of_sexp: response]
    sw net (Client_get key) ip port
  with
   | Append_response _ -> failwith "Wrong response"
   | Request_vote_response _ -> failwith "Wrong response"
   | Client_response _ -> failwith "Wrong response"
   | Client_get_response result -> result

let send_client_delete sw net key ip port =
  Or_error.try_with @@ fun () ->
  match send_rpc
    ~sexp_of_req:[%sexp_of: rpc]
    ~of_sexp_resp:[%of_sexp: response]
    sw net (Client_delete key) ip port
  with
   | Append_response _ -> failwith "Wrong response"
   | Request_vote_response _ -> failwith "Wrong response"
   | Client_response result -> result
   | Client_get_response _ -> failwith "Wrong response"

let receive_rpc_command reader =
  get_sexp [%of_sexp: rpc]  reader
