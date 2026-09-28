import os
import struct
import sys
import tempfile
import zipfile


def extra_fields(extra):
    offset = 0
    while offset < len(extra):
        kind, size = struct.unpack_from("<HH", extra, offset)
        end = offset + 4 + size
        if end > len(extra):
            raise ValueError("Truncated ZIP extra field")
        if kind == 0x0001:
            raise ValueError("ZIP64 archives are not supported")
        yield kind, extra[offset + 4:end]
        offset = end


def unix_times(extra):
    for kind, data in extra_fields(extra):
        if kind == 0x000a:
            position = 4
            while position < len(data):
                tag, length = struct.unpack_from("<HH", data, position)
                position += 4
                if tag == 1 and length == 24:
                    modified, accessed, created = struct.unpack_from("<QQQ", data, position)
                    times = (modified, accessed or modified, created or modified)
                    return [value // 10000000 - 11644473600 for value in times]
                position += length
    raise ValueError("ZIP entry has no NTFS timestamps")


def with_unix_times(extra, times, central=False):
    fields = [struct.pack("<HH", kind, len(data)) + data
              for kind, data in extra_fields(extra) if kind != 0x5455]
    # Access and creation times belong only in the local Unix timestamp field.
    if central:
        fields.append(struct.pack("<HHBI", 0x5455, 5, 7, times[0]))
    else:
        fields.append(struct.pack("<HHBIII", 0x5455, 13, 7, *times))
    return b"".join(fields)


def rewrite_headers(path):
    with zipfile.ZipFile(path) as archive, open(path, "rb") as source:
        entries = archive.infolist()
        data = source.read()
        end_offset = len(data) - 22 - len(archive.comment)
    end = bytearray(data[end_offset:])
    signature, disk, central_disk, disk_count, count, size, start, comment_size = struct.unpack_from("<4s4H2IH", end)
    if (signature != b"PK\x05\x06" or disk or central_disk or disk_count != count
            or count == 0xffff or size == 0xffffffff or start == 0xffffffff
            or count != len(entries) or start + size != end_offset):
        raise ValueError("Expected an ordinary single-disk ZIP archive")

    result = bytearray()
    offsets = {}
    cursor = 0
    for entry in sorted(entries, key=lambda item: item.header_offset):
        offset = entry.header_offset
        if offset < cursor:
            raise ValueError("Overlapping ZIP entries")
        result.extend(data[cursor:offset])
        offsets[offset] = len(result)
        header = bytearray(data[offset:offset + 30])
        if header[:4] != b"PK\x03\x04":
            raise ValueError("Invalid ZIP local header")
        name_size, extra_size = struct.unpack_from("<HH", header, 26)
        extra_start = offset + 30 + name_size
        payload_start = extra_start + extra_size
        payload_end = payload_start + entry.compress_size
        if payload_end > start:
            raise ValueError("ZIP entry overlaps the central directory")
        extra = with_unix_times(data[extra_start:payload_start], unix_times(entry.extra))
        struct.pack_into("<H", header, 28, len(extra))
        result.extend(header)
        result.extend(data[offset + 30:extra_start])
        result.extend(extra)
        result.extend(data[payload_start:payload_end])
        cursor = payload_end
    result.extend(data[cursor:start])

    central_start = len(result)
    cursor = start
    for entry in entries:
        header = bytearray(data[cursor:cursor + 46])
        if header[:4] != b"PK\x01\x02":
            raise ValueError("Invalid ZIP central header")
        name_size, extra_size, comment_size = struct.unpack_from("<HHH", header, 28)
        extra_start = cursor + 46 + name_size
        comment_start = extra_start + extra_size
        next_entry = comment_start + comment_size
        extra = with_unix_times(data[extra_start:comment_start], unix_times(entry.extra), central=True)
        old_offset, = struct.unpack_from("<I", header, 42)
        struct.pack_into("<H", header, 30, len(extra))
        struct.pack_into("<I", header, 42, offsets[old_offset])
        result.extend(header)
        result.extend(data[cursor + 46:extra_start])
        result.extend(extra)
        result.extend(data[comment_start:next_entry])
        cursor = next_entry
    if cursor != end_offset:
        raise ValueError("Unexpected ZIP central directory size")
    struct.pack_into("<II", end, 12, len(result) - central_start, central_start)
    result.extend(end)
    return result


def add_timestamps(path):
    data = rewrite_headers(path)
    descriptor, temporary = tempfile.mkstemp(suffix=".zip", dir=os.path.dirname(os.path.abspath(path)))
    try:
        with os.fdopen(descriptor, "wb") as target:
            target.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)


if __name__ == "__main__":
    add_timestamps(sys.argv[1])
