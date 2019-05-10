(* Copyright (c) 2018 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

open Sexplib.Conv

let pp_sexp fn ppf v = Fmt.pf ppf "%s" (Sexplib.Sexp.to_string_hum (fn v))

module Opam = struct
  module Remote = struct
    type t = { name : string; url : string } [@@deriving sexp]

    let pp = pp_sexp sexp_of_t
  end

  type repo =
    [ `Github of string * string
    | `Git of string
    | `Unknown of string
    | `Virtual
    | `Error of string ]
  [@@deriving sexp]

  type package = { name : string; version : string option [@default None] [@sexp_drop_default] }
  [@@deriving sexp]

  type entry = {
    package : package;
    dev_repo : repo;
    tag : Git_ref.t option; [@default None] [@sexp_drop_default]
    is_dune : bool [@default true] [@sexp_drop_default]
  }
  [@@deriving sexp]

  type pin = {
    pin : string;
    url : string option; [@default None] [@sexp_drop_default]
    tag : Git_ref.t option [@default None] [@sexp_drop_default]
  }
  [@@deriving sexp]

  type t = {
    roots : package list;
    excludes : package list;
    pins : pin list;
    pkgs : entry list;
    remotes : string list; [@default []]
    branch : string [@default "master"]
  }
  [@@deriving sexp]

  let pp_repo = pp_sexp sexp_of_repo

  let pp_package ppf { name; version } =
    match version with None -> Fmt.pf ppf "%s" name | Some v -> Fmt.pf ppf "%s.%s" name v

  let string_of_package pkg = Fmt.strf "%a" pp_package pkg

  let pp_entry = pp_sexp sexp_of_entry

  let pp = pp_sexp sexp_of_t

  let load file = Persist.load_sexp "opam duniverse" t_of_sexp file

  let save file v = Persist.save_sexp "opam duniverse" sexp_of_t file v

  let sort_uniq l = List.sort_uniq (fun a b -> String.compare a.name b.name) l
end

module Dune = struct
  type repo = {
    dir : string;
    upstream : string;
    ref : Git_ref.t [@default Git_ref.master] [@sexp_drop_default]
  }
  [@@deriving sexp]

  type t = { repos : repo list } [@@deriving sexp]

  let pp_repo = pp_sexp sexp_of_repo

  let pp = pp_sexp sexp_of_t

  let load file = Persist.load_sexp "git duniverse" t_of_sexp file

  let save file v = Persist.save_sexp "git duniverse" sexp_of_t file v
end
