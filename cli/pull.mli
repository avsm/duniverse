val cmd : unit Cmdliner.Term.t * Cmdliner.Term.info

val run :
  [< `Yes of bool ] ->
  [< `Repo of Fpath.t ] ->
  [< `Keep_clone of bool ] ->
  [< `Duniverse_repos of string list option ] ->
  unit ->
  (unit, Rresult.R.msg) result
