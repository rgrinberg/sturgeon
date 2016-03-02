open Sturgeon
open Session
open Inuit

let () =
  let fd = Unix.openfile "sturgeon.log"
      [Unix.O_CREAT; Unix.O_TRUNC; Unix.O_WRONLY] 0o660
  in
  Unix.dup2 fd Unix.stderr;
  Unix.close fd

let () =
  Recipes.text_command @@ fun ~args ~set_title k ->
  set_title "nav-server";
  let nav =
    Nav.make "Épiménide" @@ fun {Nav. title; body; nav} ->
    text body "Je mens.\n\n";
    link body "- C'est vrai."
      (fun _ -> Nav.push nav "C'est vrai !" @@
        fun {Nav. body} -> text body "C'est faux.");
    text body "\n";
    link body "- C'est faux."
      (fun _ -> Nav.push nav "C'est faux !" @@
        fun {Nav. body} -> text body "C'est vrai.");
    text body "\n"
  in
  Nav.render nav k
