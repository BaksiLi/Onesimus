"""Write a browser asset archive with stable paths, metadata and ordering."""
from pathlib import Path
import sys
import zipfile


def write_archive(directory, output):
    root = Path(directory)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob('*')):
            if path.is_file():
                entry = zipfile.ZipInfo(path.relative_to(root).as_posix())
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o100644 << 16
                archive.writestr(entry, path.read_bytes())


if __name__ == '__main__':
    write_archive(sys.argv[1], sys.argv[2])
