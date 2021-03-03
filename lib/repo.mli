open Import
(** Utility functions to extract repository specific path and values *)

type t = Fpath.t

val local_packages :
  recurse:bool ->
  ?filter:Types.Opam.package list ->
  t ->
  (Fpath.t String.Map.t, [> `Msg of string ]) result
(** Returns the locally defined opam packages as a map from package names to
    to the corresponding .opam file path.
    Only considers packages defined at the repo's root unless [recurse] is [true].
    Only considers packages listed in [filter] if the parameter is used.  *)

val dune_project : t -> Fpath.t
(** Returns the path to the dune-project file. *)

val project_name : t -> (string, [> `Msg of string ]) result
(** Returns the name of the project, as set in the dune-project. *)

val lockfile : t -> (Fpath.t, [> `Msg of string ]) result
(** Returns the path to the opam-monorepo lockfile for the given repo.
    If [name] is passed, the lockfile is ["<name>.opam.locked"] from the repo's root,
    otherwise it defaults to ["<project_name>.opam.locked"]. *)
