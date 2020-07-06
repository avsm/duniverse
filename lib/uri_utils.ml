open Rresult.R.Infix

let has_git_extension uri =
  let ext_res = Fpath.of_string (Uri.path uri) >>| fun path -> Fpath.get_ext ~multi:true path in
  match ext_res with Ok ".git" -> true | Ok _ | Error _ -> false
