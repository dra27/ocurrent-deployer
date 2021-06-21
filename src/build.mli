type org

val org :
  github:[`App of Current_github.App.t * int | `Api of Current_github.Api.t] ->
  string -> org
(** Look up a GitHub organisation by ID. *)

module Make(T : S.T) : sig
  val repo :
    ?channel:Current_slack.channel ->
    set_status:bool ->
    web_ui:(string -> Uri.t) ->
    org:org ->
    name:string ->
    (T.build_info * (string * T.deploy_info) list) list ->
    unit Current.t
    (** [repo ?channel ~set_status ~web_ui ~org ~name builds] is an OCurrent
        pipeline to handle all builds and deployments under [org/name]. Each
        build is a [(build_info, [branch, deploy_info])] pair.
        It builds every branch and PR using [T.build], and deploys the
        given branches using [T.deploy], optionally sending notifications to
        [channel]. *)
end
