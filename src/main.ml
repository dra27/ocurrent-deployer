(* This is the main entry-point for the executable.
   Edit [cmd] to set the text for "--help" and modify the command-line interface. *)

let () = Logging.init ()

(* A low-security Docker Hub user used to push images to the staging area.
   Low-security because we never rely on the tags in this repository, just the hashes. *)
let staging_user = "dra27"

let read_first_line path =
  let ch = open_in path in
  Fun.protect (fun () -> input_line ch)
    ~finally:(fun () -> close_in ch)

let read_channel_uri path =
  try
    let uri = read_first_line path in
    Current_slack.channel (Uri.of_string (String.trim uri))
  with ex ->
    Fmt.failwith "Failed to read slack URI from %S: %a" path Fmt.exn ex

(* Access control policy. *)
let has_role user role =
  match user with
  | None -> role = `Viewer || role = `Monitor         (* Unauthenticated users can only look at things. *)
  | Some user ->
    match Current_web.User.id user, role with
    | ("github:talex5"
      |"github:hannesm"
      |"github:avsm"
      |"github:kit-ty-kate"
      |"github:samoht"
      ), _ -> true        (* These users have all roles *)
    | _ -> role = `Viewer

let main config mode github slack auth sched staging_password_file =
  let vat = Capnp_rpc_unix.client_only_vat () in
  let sched = Capnp_rpc_unix.Vat.import_exn vat sched in
  let channel = Option.map read_channel_uri slack in
  let staging_auth = staging_password_file |> Option.map (fun path -> staging_user, read_first_line path) in
  let engine = Current.Engine.create ~config (Pipeline.v ~github ?notify:channel ~sched ~staging_auth) in
  let authn = Option.map Current_github.Auth.make_login_uri auth in
  let has_role =
    if auth = None then Current_web.Site.allow_all
    else has_role
  in
  let routes =
    Routes.(s "login" /? nil @--> Current_github.Auth.login auth) ::
    Routes.(s "webhooks" / s "github" /? nil @--> Current_github.webhook) ::
    Current_web.routes engine in
  let site = Current_web.Site.v ?authn ~has_role ~name:"OCurrent Deployer" routes in
  Logging.run begin
    Lwt.choose [
      Current.Engine.thread engine;  (* The main thread evaluating the pipeline. *)
      Current_web.run ~mode site;
    ]
  end

let main config mode app slack auth auth_api sched staging_password_file =
  match app, auth_api with
  | Some _, Some _
  | None, None -> `Error (true, "Either --github-token-file or --github-private-key-file, \
                                 --github-app-id, and --github-account-whitelist must be given")
  | Some app, None -> `Ok (main config mode (`App app) slack auth sched staging_password_file)
  | None, Some api -> `Ok (main config mode (`Api api) slack auth sched staging_password_file)

(* Command-line parsing *)

open Cmdliner

let slack =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:"A file containing the URI of the endpoint for status updates"
    ~docv:"URI-FILE"
    ["slack"]

let submission_service =
  Arg.required @@
  Arg.opt Arg.(some Capnp_rpc_unix.sturdy_uri) None @@
  Arg.info
    ~doc:"The submission.cap file for the build scheduler service"
    ~docv:"FILE"
    ["submission-service"]

let staging_password =
  Arg.value @@
  Arg.opt Arg.(some file) None @@
  Arg.info
    ~doc:(Printf.sprintf "A file containing the password for the %S Docker Hub user" staging_user)
    ~docv:"FILE"
    ["staging-password-file"]

let cmd =
  let doc = "build and deploy services from Git" in
  Term.(ret (const main $ Current.Config.cmdliner $ Current_web.cmdliner $
        Current_github.App.cmdliner_opt $ slack $ Current_github.Auth.cmdliner $
        Current_github.Api.cmdliner_opt $ submission_service $ staging_password)),
  Term.info "deploy" ~doc

let () = Term.(exit @@ eval cmd)
