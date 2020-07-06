open Duniverse_lib
open Astring
open Cmdliner

module Arg = struct
  let named f = Term.(app (const f))

  let fpath = Arg.conv ~docv:"PATH" (Fpath.of_string, Fpath.pp)

  let repo =
    let doc = "Path to Git repository to store vendored code in." in
    named
      (fun x -> `Repo x)
      Arg.(
        value & opt fpath (Fpath.v (Sys.getcwd ())) & info [ "r"; "repo" ] ~docv:"TARGET_REPO" ~doc)

  let yes =
    let doc = "Do not prompt for confirmation and always assume yes" in
    named (fun x -> `Yes x) Arg.(value & flag & info [ "y"; "yes" ] ~doc)

  let non_empty_list_opt = Term.pure (function [] -> None | l -> Some l)

  let duniverse_repos =
    let docv = "REPOSITORIES" in
    let doc =
      "The list of $(docv) from your duniverse to process. If none is provided, all will be \
       processed."
    in
    named
      (fun x -> `Duniverse_repos x)
      Term.(non_empty_list_opt $ Arg.(value & pos_all string [] & info ~doc ~docv []))

  let no_cache =
    let doc = "Run without using the duniverse global cache" in
    named (fun x -> `No_cache x) Arg.(value & flag & info ~doc [ "no-cache" ])

  let opam_repo =
    let doc =
      "URL or path to the Duniverse opam-repository that has overrides for packages that have not \
       yet been ported to Dune upstream."
    in
    named
      (fun x -> `Opam_repo (Uri.of_string x))
      Arg.(
        value & opt string Config.duniverse_opam_repo & info [ "opam-repo" ] ~docv:"OPAM_REPO" ~doc)

  let cache_env_var ?(windows_only = false) ~priority ~extra_path ~var () =
    let windows_only = if windows_only then " (only on Windows)" else "" in
    let doc =
      Printf.sprintf
        "Used to determine the cache location%s. It has priority %s. If set, the cache will be \
         read from/written to $(b,\\$)$(env)$(b,/%s)."
        windows_only priority extra_path
    in
    Term.env_info ~doc var

  let dev_repo =
    let parse s =
      match Opam.Dev_repo.from_string s with
      | { vcs = Some Git; uri = dev_repo_uri } -> (
          match Uri.host dev_repo_uri with
          | Some _host -> Ok dev_repo_uri
          | None -> Error (`Msg "dev-repo without host") )
      | { vcs = None | Some (Other _); _ } -> Error (`Msg "dev-repo doesn't use git as a VCS")
    in
    Arg.conv ~docv:"DEV_REPO" (parse, Uri.pp_hum)

  let caches =
    let duniverse_cache =
      cache_env_var ~priority:"1 (the highest)" ~extra_path:"duniverse" ~var:"DUNIVERSE_CACHE" ()
    in
    let xdg_cache = cache_env_var ~priority:"2" ~extra_path:"duniverse" ~var:"XDG_CACHE_HOME" () in
    let home_cache = cache_env_var ~priority:"3" ~extra_path:".cache/duniverse" ~var:"HOME" () in
    let app_data_cache =
      cache_env_var ~windows_only:true ~priority:"4 (the lowest)"
        ~extra_path:"Local Settings/Cache/duniverse" ~var:"AppData" ()
    in
    [ duniverse_cache; xdg_cache; home_cache; app_data_cache ]

  let thread_safe_reporter reporter =
    let lock = Mutex.create () in
    let { Logs.report } = reporter in
    let oui src level ~over k msgf =
      Mutex.lock lock;
      let x = report src level ~over k msgf in
      Mutex.unlock lock;
      x
    in
    Logs.{ report = oui }

  let setup_logs () =
    Printexc.record_backtrace true;
    let setup_log style_renderer level =
      Fmt_tty.setup_std_outputs ?style_renderer ();
      Logs.set_level level;
      Logs.set_reporter (thread_safe_reporter (Logs_fmt.reporter ()))
    in
    let global_option_section = "COMMON OPTIONS" in
    Term.(
      const setup_log
      $ Fmt_cli.style_renderer ~docs:global_option_section ()
      $ Logs_cli.level ~docs:global_option_section ())

  let version =
    match Build_info.V1.version () with
    | None -> "n/a"
    | Some v -> Build_info.V1.Version.to_string v
end

module Logs = struct
  let app ?src f =
    Logs.app ?src (fun l ->
        f (fun ?header ?tags fmt -> l ?header ?tags ("%a" ^^ fmt) Duniverse_lib.Styled_pp.header ()))
end

(** Filters the duniverse according to the CLI provided list of repos *)
let filter_duniverse ~to_consider src_deps =
  match to_consider with
  | None -> Ok src_deps
  | Some to_consider -> (
      let repos_map =
        String.Map.of_list (List.map (fun src -> (src.Duniverse.Deps.Source.dir, src)) src_deps)
      in
      let unmatched, found =
        List.fold_left
          (fun (unmatched, found) asked ->
            match String.Map.find asked repos_map with
            | None -> (asked :: unmatched, found)
            | Some f -> (unmatched, f :: found))
          ([], []) to_consider
      in
      match unmatched with
      | [] -> Ok found
      | _ ->
          let sep fmt () = Fmt.pf fmt " " in
          Rresult.R.error_msgf "The following repos are not in your duniverse: %a"
            Fmt.(list ~sep string)
            unmatched )

let get_cache ~no_cache = if no_cache then Ok Cloner.no_cache else Cloner.get_cache ()
