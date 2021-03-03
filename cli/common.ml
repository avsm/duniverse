open Import

module Arg = struct
  let named f = Cmdliner.Term.(app (const f))

  let fpath = Cmdliner.Arg.conv ~docv:"PATH" (Fpath.of_string, Fpath.pp)

  let package =
    let parse s = Ok (Types.Opam.package_from_string s) in
    Cmdliner.Arg.conv ~docv:"PACKAGE" (parse, Types.Opam.pp_package)

  let repo =
    let doc = "Path to Git repository to store vendored code in." in
    named
      (fun x -> `Repo x)
      Cmdliner.Arg.(
        value & opt fpath (Fpath.v (Sys.getcwd ())) & info [ "r"; "repo" ] ~docv:"TARGET_REPO" ~doc)

  let lockfile =
    let doc = "Path to the lockfile to use or generate. Defaults $(b,<project-name>.opam.locked)" in
    named
      (fun x -> `Lockfile x)
      Cmdliner.Arg.(value & opt (some fpath) None & info [ "l"; "lockfile" ] ~doc)

  let yes =
    let doc = "Do not prompt for confirmation and always assume yes" in
    named (fun x -> `Yes x) Cmdliner.Arg.(value & flag & info [ "y"; "yes" ] ~doc)

  let non_empty_list_opt = Cmdliner.Term.pure (function [] -> None | l -> Some l)

  let duniverse_repos =
    let open Cmdliner in
    let docv = "REPOSITORIES" in
    let doc =
      "The list of $(docv) from your duniverse to process. If none is provided, all will be \
       processed."
    in
    named
      (fun x -> `Duniverse_repos x)
      Term.(non_empty_list_opt $ Arg.(value & pos_all string [] & info ~doc ~docv []))

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
    let open Cmdliner.Term in
    const setup_log
    $ Fmt_cli.style_renderer ~docs:global_option_section ()
    $ Logs_cli.level ~docs:global_option_section ()

  let version =
    match Build_info.V1.version () with
    | None -> "n/a"
    | Some v -> Build_info.V1.Version.to_string v
end

module Logs = struct
  let app ?src f =
    Logs.app ?src (fun l ->
        f (fun ?header ?tags fmt -> l ?header ?tags ("%a" ^^ fmt) Duniverse_lib.Pp.Styled.header ()))
end

(** Filters the duniverse according to the CLI provided list of repos *)
let filter_duniverse ~to_consider (duniverse : Duniverse.t) =
  match to_consider with
  | None -> Ok duniverse
  | Some to_consider -> (
      let repos_map = String.Map.of_list_map_exn duniverse ~f:(fun src -> (src.dir, src)) in
      let unmatched, found =
        List.partition_map to_consider ~f:(fun asked ->
            match String.Map.find repos_map asked with
            | None -> Left asked
            | Some found -> Right found)
      in
      match unmatched with
      | [] -> Ok found
      | _ ->
          let sep fmt () = Fmt.pf fmt " " in
          Rresult.R.error_msgf "The following repos are not in your duniverse: %a"
            Fmt.(list ~sep string)
            unmatched )

let lockfile ~explicit_lockfile repo =
  match explicit_lockfile with
  | Some path -> Ok path
  | None -> (
      match Repo.lockfile repo with
      | Ok path -> Ok path
      | Error (`Msg msg) ->
          Rresult.R.error_msgf
            "Couldn't not infer lockfile path from project name: %s\n\n\
            \         Either set a project name in your dune-project file or explicitly\n\
            \         set the path to the lockfile using --lockfile/-l." msg )
