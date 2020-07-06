open Astring
open Sexplib.Conv
open Rresult.R.Infix

let result_list_map f t =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | x :: xs -> f x >>= fun x -> loop (x :: acc) xs
  in
  loop [] t

module Ls_remote = struct
  let non_packed_suffix = "^{}"

  let ref_arg ref = Bos.Cmd.(v ref % (ref ^ non_packed_suffix))

  let parse_output_line s =
    match String.fields ~empty:false s with
    | [ commit; ref ] -> Ok (commit, ref)
    | _ -> Error (`Msg (Printf.sprintf "Invalid git ls-remote output line: %S" s))

  type search_result = { maybe_packed : string option; not_packed : string option }

  let interpret_search_result sr =
    match sr with
    | { maybe_packed = None; not_packed = None } -> None
    | { maybe_packed = Some commit; not_packed = None }
    | { maybe_packed = _; not_packed = Some commit } ->
        Some commit

  let search_ref target lines =
    let target_not_packed = target ^ non_packed_suffix in
    let f acc (commit, full_ref) =
      if String.equal full_ref target then { acc with maybe_packed = Some commit }
      else if String.equal full_ref target_not_packed then { acc with not_packed = Some commit }
      else acc
    in
    List.fold_left f { maybe_packed = None; not_packed = None } lines

  let commit_pointed_by ~ref output_lines =
    match output_lines with
    | [ "" ] -> Error `No_such_ref
    | _ -> (
        result_list_map parse_output_line output_lines >>= fun parsed_lines ->
        let search prefix =
          let result = search_ref (prefix ^ ref) parsed_lines in
          interpret_search_result result
        in
        match (search "refs/tags/", search "refs/heads/") with
        | Some _, Some _ -> Error `Multiple_such_refs
        | Some commit, None | None, Some commit -> Ok commit
        | None, None -> Error `No_such_ref )
end

module Ref = struct
  type t = string [@@deriving sexp]

  let equal = String.equal

  let pp = Format.pp_print_string

  type resolved = { t : t; commit : string } [@@deriving sexp]

  let equal_resolved r r' = equal r.t r'.t && String.equal r.commit r'.commit

  let pp_resolved fmt resolved =
    Format.fprintf fmt "@[<hov 2>{ t = %a;@ commit = %s }@]" pp resolved.t resolved.commit
end
