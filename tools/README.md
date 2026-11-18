# Delivery build helpers

Use the host's dependency manager to verify the pinned Kit checkout before
loading the helper. `runpy.run_path(str(kit / "tools/delivery_support.py"))`
loads the source without creating bytecode in the managed checkout.

| Function | Contract |
| --- | --- |
| `copy_files(source_root, stage_root, files)` | Copy ordered `(source, destination)` relative path pairs with the original `copy2` metadata. |
| `write_zip(source_root, stage_root, archive, members)` | Write ordered `(source, member)` pairs to a relative archive path. ZIP members use the fixed 1980 timestamp, mode 0644 and DEFLATE. |
| `hash_files(root, paths)` | Return relative-path SHA-256 values in caller order. |
| `inventory(stage_root)` | Return SHA-256 values for all staged files in sorted path order. |

The caller selects suffixes, source paths and destination names. Supply real
directory roots and an existing private stage with all required destination
parent directories. The helpers reject symbolic links, escaping paths and
replacement of existing output files. The host owns the stage during assembly.
Package layouts, manifest fields, timestamps, final publication and runtime
startup stay with the host. Use a fresh stage for each comparison.

Run `python3 -B -m unittest discover -s tools/tests -v` from the Kit root.
The normal Kit core check also runs these tests.
