open Duniverse_lib
open Rresult.R.Infix
open Cmdliner

let debug_update ~src_dep ~new_ref =
  let repo = src_dep.Duniverse.Deps.Source.dir in
  let ref = src_dep.ref.Git.Ref.t in
  let old_commit = src_dep.ref.commit in
  let new_commit = new_ref.Git.Ref.commit in
  Logs.debug (fun l ->
      l "Updated %a#%a from %a to %a" Styled_pp.package_name repo Styled_pp.branch ref
        Styled_pp.commit old_commit Styled_pp.commit new_commit)

let should_update ~to_update src_dep =
  match to_update with None -> true | Some set -> List.mem src_dep set

let update ~total ~updated ~to_update src_dep =
  let ref : Duniverse.resolved = src_dep.Duniverse.Deps.Source.ref in
  if should_update ~to_update src_dep then (
    incr total;
    Exec.git_resolve ~remote:src_dep.upstream ~ref:ref.t >>= fun new_ref ->
    if not (String.equal ref.commit new_ref.commit) then incr updated;
    debug_update ~src_dep ~new_ref;
    Ok { src_dep with ref = new_ref } )
  else Ok src_dep

let run (`Repo repo) (`Duniverse_repos duniverse_repos) () =
  let duniverse_file = Fpath.(repo // Config.duniverse_file) in
  Common.Logs.app (fun l ->
      l "Updating %a to track the latest commits" Styled_pp.path duniverse_file);
  Duniverse.load ~file:duniverse_file >>= function
  | { deps = { duniverse = []; _ }; _ } ->
      Common.Logs.app (fun l -> l "No source dependencies, nothing to be done here!");
      Ok ()
  | { deps = { duniverse; _ }; _ } as dune_get ->
      let total = ref 0 in
      let updated = ref 0 in
      ( match duniverse_repos with
      | None -> Ok None
      | _ -> Common.filter_duniverse ~to_consider:duniverse_repos duniverse >>| Option.some )
      >>= fun to_update ->
      List.fold_left
        (fun acc e ->
          acc >>= fun acc ->
          update ~total ~updated ~to_update e >>| fun e -> e :: acc)
        (Ok []) (List.rev duniverse)
      >>= fun duniverse ->
      if !updated = 0 then (
        Common.Logs.app (fun l -> l "%a is already up-to-date!" Styled_pp.path duniverse_file);
        Ok () )
      else (
        Common.Logs.app (fun l ->
            l "%a/%a source repositories tracked branch were updated" (Styled_pp.good Fmt.int)
              !updated
              Fmt.(styled `Blue int)
              !total);
        let dune_get = { dune_get with deps = { dune_get.deps with duniverse } } in
        Duniverse.save ~file:duniverse_file dune_get )

let term =
  Term.(
    term_result (const run $ Common.Arg.repo $ Common.Arg.duniverse_repos $ Common.Arg.setup_logs ()))

let info =
  let doc =
    "update the commit hash corresponding to the tracked branch/tag for each source dependency"
  in
  let exits = Term.default_exits in
  let man =
    [
      `S Manpage.s_description;
      `P
        "This command updates your dune-get file with the latest commit hash for each repo's \
         tracked branch or tag.";
      `P
        "Note that it does not update your duniverse and you have to run $(b,duniverse pull)again \
         to bring it up to speed with these changes.";
    ]
  in
  Term.info "update" ~doc ~exits ~man

let cmd = (term, info)
