"""Build-time file operations for a private delivery stage."""

from contextlib import contextmanager
import hashlib
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import shutil
import stat
import zipfile


def _root(path):
    root = Path(path).absolute()
    if root.resolve(strict=True) != root or not stat.S_ISDIR(root.lstat().st_mode):
        raise ValueError(f"Expected a real directory root: {root}")
    return root


def _relative(path):
    name = os.fspath(path)
    if not isinstance(name, str):
        raise TypeError("Delivery paths must be text")
    relative = PurePosixPath(name)
    if (
        not relative.parts
        or relative.is_absolute()
        or ".." in relative.parts
        or relative.as_posix() != name
        or "\\" in name
        or "\0" in name
        or PureWindowsPath(name).drive
    ):
        raise ValueError(f"Expected a canonical relative path: {name!r}")
    return relative


def _under(root, relative):
    parent = root
    for part in relative.parts[:-1]:
        parent /= part
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError(f"Expected a real directory: {parent}")
    return parent / relative.name


def _source(root, relative):
    source = _under(root, relative)
    if not stat.S_ISREG(source.lstat().st_mode):
        raise ValueError(f"Expected a regular file: {source}")
    return source


def _destination(root, relative):
    destination = _under(root, relative)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Delivery file already exists: {destination}")
    return destination


@contextmanager
def _new_file(destination):
    stream = destination.open("xb")
    try:
        with stream:
            yield stream
    except BaseException:
        destination.unlink()
        raise


def copy_files(source_root, stage_root, files):
    """Copy ordered (source, destination) pairs, preserving copy2 metadata."""
    source_root, stage_root = _root(source_root), _root(stage_root)
    planned = []
    destinations = set()
    for source, destination in files:
        target = _destination(stage_root, _relative(destination))
        if target in destinations:
            raise ValueError(f"Duplicate copy destination: {target}")
        destinations.add(target)
        planned.append((_source(source_root, _relative(source)), target))
    completed = []
    try:
        for source, target in planned:
            with source.open("rb") as incoming, _new_file(target) as outgoing:
                shutil.copyfileobj(incoming, outgoing)
                outgoing.flush()
                shutil.copystat(source, target)
            completed.append(target)
    except BaseException:
        for target in reversed(completed):
            target.unlink()
        raise


def write_zip(source_root, stage_root, archive, members):
    """Write ordered (source, member) pairs with the hosts' fixed ZIP metadata."""
    source_root, stage_root = _root(source_root), _root(stage_root)
    target = _destination(stage_root, _relative(archive))
    planned = []
    names = set()
    for source, member in members:
        name = _relative(member).as_posix()
        if name in names:
            raise ValueError(f"Duplicate ZIP member: {name}")
        names.add(name)
        planned.append((_source(source_root, _relative(source)), name))
    with _new_file(target) as output, zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as zipped:
        for source, name in planned:
            entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o644 << 16
            zipped.writestr(entry, source.read_bytes())


def _sha256(path):
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def hash_files(root, paths):
    """Return SHA-256 by caller-selected relative path and insertion order."""
    root = _root(root)
    result = {}
    for path in paths:
        relative = _relative(path)
        result[relative.as_posix()] = _sha256(_source(root, relative))
    return result


def inventory(stage_root):
    """Inventory every staged regular file in the existing packager path order."""
    stage_root = _root(stage_root)
    result = {}
    for path in sorted(stage_root.rglob("*")):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError(f"Expected a regular staged file: {path}")
        result[path.relative_to(stage_root).as_posix()] = _sha256(path)
    return result
