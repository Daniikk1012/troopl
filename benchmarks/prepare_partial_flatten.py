"""Prepare an isolated one-level-flattening experiment from a git revision.

Run: python benchmarks/prepare_partial_flatten.py REV NEW_DIRECTORY
The destination must not exist. It is an experiment, not a runtime option.
Run the exported test suite and benchmark_storage/benchmark_layout there.
"""
import io
from pathlib import Path
import subprocess
import sys
import tarfile

revision, destination = sys.argv[1:]
destination = Path(destination)
destination.mkdir(parents=True, exist_ok=False)
archive = subprocess.check_output(["git", "archive", revision])
with tarfile.open(fileobj=io.BytesIO(archive)) as files:
    files.extractall(destination, filter="data")
path = destination / "lib" / "value.ml"
source = path.read_text()
start = source.index("let bounded storage =")
end = source.index("let add_method_id", start)
source = source[:start] + """let flatten storage =
  let table = Hashtbl.create 16 in
  iter_selectors (fun selector ->
    if not (Hashtbl.mem table selector) then
      Hashtbl.add table selector (resolve storage selector)) storage;
  Table table

(* Reduce every deepest path by exactly one level. Flatten only depth-two
   subtrees, and rebuild their ancestors without invoking guest methods. *)
let rec reduce_one storage =
  if depth storage <= 2 then flatten storage else
  match storage with
  | Shared (base, _) ->
      let base = reduce_one base in Shared (base, depth base + 1)
  | Overlay (delta, base, _) ->
      let base = reduce_one base in Overlay (delta, base, depth base + 1)
  | Bound (base, env, before, _) ->
      let base = reduce_one base in Bound (base, env, before, depth base + 1)
  | Merge (later, earlier, _) ->
      let limit = depth storage - 2 in
      let reduce child =
        if depth child > limit then reduce_one child else child in
      let later = reduce later and earlier = reduce earlier in
      Merge (later, earlier, 1 + max (depth later) (depth earlier))
  | Empty | Table _ | Numeric _ -> assert false

let bounded storage =
  if depth storage <= max_depth then storage else reduce_one storage

""" + source[end:]
path.write_text(source)
print(destination)
