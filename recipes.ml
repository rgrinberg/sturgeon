let command ?greetings ?cogreetings () =
  let stdin = Sexp.of_channel stdin in
  let stdout sexp =
    Sexp.tell_sexp print_string sexp;
    print_newline ();
    flush stdout
  in
  let stdin', status = Session.connect ?greetings ?cogreetings stdout in
  let rec aux () =
    match stdin () with
    | None -> exit 0
    | Some sexp ->
      stdin' sexp;
      if Session.pending_sessions status > 0 then
        aux ()
      else exit 0
  in
  aux ()

let text_command f =
  let open Sexp in
  command ~cogreetings:(function
      | C (S "textbuf", C (session, args)) ->
        let cursor, set_title = Stui.accept_cursor session in
        f ~args ~set_title cursor
      | sexp -> Session.cancel sexp
    )
    ()

open Lwt

type server = {
  greetings: (unit -> Session.t) option;
  cogreetings: (Session.t -> unit) option;

  mutable socket: Lwt_unix.file_descr option;
}

let server ?greetings ?cogreetings name =
  let dir = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "sturgeon.%d" (Unix.getuid ())) in
  if not (Sys.file_exists dir) then
    Unix.mkdir dir 0o770;
  let name = Filename.concat dir
      (Printf.sprintf "%s.%d.sturgeon" name (Unix.getpid ())) in
  let socket = Lwt_unix.socket Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let addr = Lwt_unix.ADDR_UNIX name in
  Lwt_unix.bind socket addr;
  at_exit (fun () -> Unix.unlink name);
  Lwt_unix.listen socket 3;
  { socket = Some socket; greetings; cogreetings }

let accept server =
  match server.socket with
  | None -> return_unit
  | Some socket ->
    Lwt_unix.accept socket >|= fun (client, _) ->
    let o, sink = Lwt_stream.create () in
    let ic = Lwt_io.of_fd ~mode:Lwt_io.input client in
    let oc = Lwt_io.of_fd ~mode:Lwt_io.output client in
    Lwt.async (fun () ->
        let rec loop () =
          Lwt_stream.get o >>= function
          | None -> Lwt_io.close oc
          | Some chunk ->
              let chunks = chunk :: Lwt_stream.get_available o in
              let string = String.concat "" chunks in
              Lwt_io.write_from_string_exactly oc string 0 (String.length string)
              >>= loop
        in
        loop ()
      );
    let send sexp =
      Sexp.tell_sexp (fun s -> sink (Some s)) sexp;
      sink (Some "\n")
    in
    let cogreetings = server.cogreetings in
    let greetings = match server.greetings with
      | None -> None
      | Some f -> Some (f ())
    in
    let received, status = Session.connect ?greetings ?cogreetings send in
    let rec loop () =
      Lwt_io.read_line_opt ic >>= function
      | None -> Lwt_unix.close client
      | Some str ->
        received (Sexp.of_string str);
        loop ()
    in
    Lwt.async loop

let text_server name f =
  let open Sexp in
  server ~cogreetings:(function
      | C (S "textbuf", C (session, args)) ->
        let cursor, set_title = Stui.accept_cursor session in
        f ~args ~set_title cursor
      | sexp -> Session.cancel sexp
    ) name
