#!/usr/bin/env python3
"""Relabel arm64 Google ML Kit objects for the current Apple platform.

Google ML Kit's older static frameworks contain arm64 objects marked for the
device platform only. Xcode 27's Apple Silicon simulators also use arm64, so
the architecture is usable but the Mach-O platform marker is rejected. Newer
objects can be relabeled in place through LC_BUILD_VERSION. Older objects use
LC_VERSION_MIN_IPHONEOS instead; converting that command grows the load-command
area, so this script also rewrites Mach-O file offsets, archive members, archive
symbol indexes, and fat-slice offsets.

Run from an Xcode build phase:
  patch_arm64_simulator.py --platform "$PLATFORM_NAME" --pods-root "$SRCROOT"
"""

import argparse
import glob
import os
import stat
import struct
import sys
import tempfile

FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_SYMSEG = 0x03
LC_TWOLEVEL_HINTS = 0x16
LC_CODE_SIGNATURE = 0x1D
LC_SEGMENT_SPLIT_INFO = 0x1E
LC_ENCRYPTION_INFO = 0x21
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x80000022
LC_FUNCTION_STARTS = 0x26
LC_DATA_IN_CODE = 0x29
LC_ENCRYPTION_INFO_64 = 0x2C
LC_DYLIB_CODE_SIGN_DRS = 0x2B
LC_LINKER_OPTIMIZATION_HINT = 0x2E
LC_NOTE = 0x31
LC_BUILD_VERSION = 0x32
LC_DYLD_EXPORTS_TRIE = 0x80000033
LC_DYLD_CHAINED_FIXUPS = 0x80000034
LC_VERSION_MIN_IPHONEOS = 0x25
PLATFORM_IOS = 2
PLATFORM_IOS_SIMULATOR = 7
CPU_TYPE_ARM64 = 0x0100000C
AR_MAGIC = b'!<arch>\n'
AR_HEADER_SIZE = 60

AR_INDEX_NAMES = {
    b'__.SYMDEF',
    b'__.SYMDEF SORTED',
    b'__.SYMDEF_64',
    b'__.SYMDEF_64 SORTED',
}

PLATFORM_BY_SDK = {
    'iphoneos': PLATFORM_IOS,
    'iphonesimulator': PLATFORM_IOS_SIMULATOR,
}


def _shift_offset(value, insertion, delta):
    if value >= insertion:
        return value + delta
    return value


def _shift_u32_field(commands, offset, insertion, delta):
    value = struct.unpack_from('<I', commands, offset)[0]
    shifted = _shift_offset(value, insertion, delta)
    if shifted > 0xFFFFFFFF:
        raise ValueError('Mach-O file offset exceeds 32-bit range')
    struct.pack_into('<I', commands, offset, shifted)


def _shift_u64_field(commands, offset, insertion, delta):
    value = struct.unpack_from('<Q', commands, offset)[0]
    shifted = _shift_offset(value, insertion, delta)
    if shifted > 0xFFFFFFFFFFFFFFFF:
        raise ValueError('Mach-O file offset exceeds 64-bit range')
    struct.pack_into('<Q', commands, offset, shifted)


def _shift_macho_file_offsets(commands, insertion, delta):
    """Update file offsets after inserting bytes at the load-command boundary."""
    offset = 0
    while offset + 8 <= len(commands):
        cmd, cmdsize = struct.unpack_from('<II', commands, offset)
        if cmdsize < 8 or offset + cmdsize > len(commands):
            raise ValueError('invalid Mach-O load command while shifting offsets')

        if cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise ValueError('short LC_SEGMENT_64 command')
            fileoff = struct.unpack_from('<Q', commands, offset + 32)[0]
            filesize = struct.unpack_from('<Q', commands, offset + 40)[0]
            new_fileoff = _shift_offset(fileoff, insertion, delta)
            if new_fileoff > 0xFFFFFFFFFFFFFFFF:
                raise ValueError('Mach-O segment offset exceeds 64-bit range')
            struct.pack_into('<Q', commands, offset + 32, new_fileoff)
            if fileoff < insertion < fileoff + filesize:
                struct.pack_into('<Q', commands, offset + 40, filesize + delta)

            nsects = struct.unpack_from('<I', commands, offset + 64)[0]
            sections_end = 72 + nsects * 80
            if sections_end > cmdsize:
                raise ValueError('LC_SEGMENT_64 sections exceed command size')
            for section in range(nsects):
                section_offset = offset + 72 + section * 80
                _shift_u32_field(commands, section_offset + 48,
                                 insertion, delta)
                _shift_u32_field(commands, section_offset + 56,
                                 insertion, delta)

        elif cmd == LC_SYMTAB:
            if cmdsize < 24:
                raise ValueError('short LC_SYMTAB command')
            _shift_u32_field(commands, offset + 8, insertion, delta)
            _shift_u32_field(commands, offset + 16, insertion, delta)

        elif cmd == LC_DYSYMTAB:
            if cmdsize < 80:
                raise ValueError('short LC_DYSYMTAB command')
            # The command alternates symbol indexes/counts with file offsets.
            # Only the *off fields move when bytes are inserted in the object.
            for field in (32, 40, 48, 56, 64, 72):
                _shift_u32_field(commands, offset + field, insertion, delta)

        elif cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
            if cmdsize < 48:
                raise ValueError('short LC_DYLD_INFO command')
            for field in (8, 16, 24, 32, 40):
                _shift_u32_field(commands, offset + field, insertion, delta)

        elif cmd in (
            LC_SYMSEG,
            LC_TWOLEVEL_HINTS,
            LC_CODE_SIGNATURE,
            LC_SEGMENT_SPLIT_INFO,
            LC_FUNCTION_STARTS,
            LC_DATA_IN_CODE,
            LC_ENCRYPTION_INFO,
            LC_ENCRYPTION_INFO_64,
            LC_DYLIB_CODE_SIGN_DRS,
            LC_LINKER_OPTIMIZATION_HINT,
            LC_DYLD_EXPORTS_TRIE,
            LC_DYLD_CHAINED_FIXUPS,
        ):
            if cmdsize < 16:
                raise ValueError('short load command with a file offset')
            _shift_u32_field(commands, offset + 8, insertion, delta)

        elif cmd == LC_NOTE:
            if cmdsize < 40:
                raise ValueError('short LC_NOTE command')
            _shift_u64_field(commands, offset + 24, insertion, delta)

        offset += cmdsize

    if offset != len(commands):
        raise ValueError('Mach-O load-command size does not match commands')


def _build_version_command(old_command, target_platform):
    old_cmdsize = struct.unpack_from('<I', old_command, 4)[0]
    if old_cmdsize < 16:
        raise ValueError('short LC_VERSION_MIN_IPHONEOS command')
    version, sdk = struct.unpack_from('<II', old_command, 8)
    new_cmdsize = max(24, old_cmdsize)
    command = bytearray(new_cmdsize)
    command[:min(len(old_command), new_cmdsize)] = old_command[:new_cmdsize]
    struct.pack_into(
        '<IIIIII', command, 0, LC_BUILD_VERSION, new_cmdsize,
        target_platform, version, sdk, 0)
    return bytes(command)


def _relabel_macho(data, target_platform):
    """Relabel one arm64 Mach-O object, growing old load commands if needed."""
    if len(data) < 32 or struct.unpack_from('<I', data, 0)[0] != MH_MAGIC_64:
        return data, False

    cputype = struct.unpack_from('<i', data, 4)[0]
    if cputype != CPU_TYPE_ARM64:
        return data, False

    ncmds, sizeofcmds = struct.unpack_from('<II', data, 16)
    old_end = 32 + sizeofcmds
    if old_end > len(data):
        raise ValueError('Mach-O load commands exceed object size')

    old_commands = data[32:old_end]
    offset = 0
    has_build_version = False
    old_version_commands = []
    while offset < len(old_commands) and len(old_version_commands) <= ncmds:
        if offset + 8 > len(old_commands):
            raise ValueError('truncated Mach-O load command')
        cmd, cmdsize = struct.unpack_from('<II', old_commands, offset)
        if cmdsize < 8 or offset + cmdsize > len(old_commands):
            raise ValueError('invalid Mach-O load command size')
        if cmd == LC_BUILD_VERSION:
            if cmdsize < 12:
                raise ValueError('short LC_BUILD_VERSION command')
            has_build_version = True
        elif cmd == LC_VERSION_MIN_IPHONEOS:
            old_version_commands.append((offset, cmdsize))
        offset += cmdsize

    if offset != len(old_commands) or len(old_version_commands) > ncmds:
        raise ValueError('Mach-O load-command count does not match commands')

    if has_build_version:
        commands = bytearray(old_commands)
        changed = False
        offset = 0
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from('<II', commands, offset)
            if cmd == LC_BUILD_VERSION:
                platform = struct.unpack_from('<I', commands, offset + 8)[0]
                if platform in (PLATFORM_IOS, PLATFORM_IOS_SIMULATOR) \
                        and platform != target_platform:
                    struct.pack_into('<I', commands, offset + 8,
                                     target_platform)
                    changed = True
            offset += cmdsize
        if not changed:
            return data, False
        return data[:32] + bytes(commands) + data[old_end:], True

    if not old_version_commands:
        return data, False

    new_commands = bytearray()
    offset = 0
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', old_commands, offset)
        command = old_commands[offset:offset + cmdsize]
        if cmd == LC_VERSION_MIN_IPHONEOS:
            new_commands.extend(_build_version_command(command, target_platform))
        else:
            new_commands.extend(command)
        offset += cmdsize

    delta = len(new_commands) - sizeofcmds
    _shift_macho_file_offsets(new_commands, old_end, delta)

    header = bytearray(data[:32])
    struct.pack_into('<I', header, 20, len(new_commands))
    return bytes(header) + bytes(new_commands) + data[old_end:], True


def _archive_member_name(header, body):
    raw_name = header[:16].rstrip()
    if raw_name.startswith(b'#1/'):
        try:
            name_size = int(raw_name[3:])
        except ValueError as exc:
            raise ValueError('invalid extended archive member name') from exc
        if name_size > len(body):
            raise ValueError('archive member name exceeds member size')
        name = body[:name_size].rstrip(b'\0')
        return name, name_size
    return raw_name.rstrip(b'/ '), 0


def _rewrite_ranlib_index(body, name_size, old_to_new):
    """Update Darwin ar symbol-index member offsets without changing its size."""
    name = body[:name_size].rstrip(b'\0')
    payload = bytearray(body[name_size:])
    is_64 = name in (b'__.SYMDEF_64', b'__.SYMDEF_64 SORTED')
    if is_64:
        if len(payload) < 16:
            raise ValueError('short 64-bit archive symbol index')
        ranlib_size = struct.unpack_from('<Q', payload, 0)[0]
        entry_size = 16
        string_size_offset = 8 + ranlib_size
        entry_offset = 8
        unpack_size = 'Q'
        unpack_offset = 'Q'
    else:
        if len(payload) < 8:
            raise ValueError('short archive symbol index')
        ranlib_size = struct.unpack_from('<I', payload, 0)[0]
        entry_size = 8
        string_size_offset = 4 + ranlib_size
        entry_offset = 4
        unpack_size = 'I'
        unpack_offset = 'I'

    if ranlib_size % entry_size != 0 \
            or string_size_offset + struct.calcsize('<' + unpack_size) > len(payload):
        raise ValueError('invalid archive symbol index size')
    string_size = struct.unpack_from('<' + unpack_size, payload,
                                     string_size_offset)[0]
    if string_size_offset + struct.calcsize('<' + unpack_size) + string_size \
            > len(payload):
        raise ValueError('archive symbol string table exceeds member size')

    entry_count = ranlib_size // entry_size
    for index in range(entry_count):
        member_offset = entry_offset + index * entry_size
        offset_field = member_offset + (8 if is_64 else 4)
        old_offset = struct.unpack_from('<' + unpack_offset, payload,
                                        offset_field)[0]
        if old_offset not in old_to_new:
            raise ValueError(
                f'archive symbol index references unknown member offset '
                f'{old_offset}')
        struct.pack_into('<' + unpack_offset, payload, offset_field,
                         old_to_new[old_offset])

    return body[:name_size] + bytes(payload)


def _relabel_archive(data, target_platform):
    if not data.startswith(AR_MAGIC):
        return data, 0

    members = []
    position = len(AR_MAGIC)
    while position < len(data):
        if position + AR_HEADER_SIZE > len(data):
            raise ValueError('truncated archive member header')
        header = data[position:position + AR_HEADER_SIZE]
        if header[58:60] != b'`\n':
            raise ValueError('invalid archive member trailer')
        try:
            member_size = int(header[48:58].decode('ascii').strip())
        except ValueError as exc:
            raise ValueError('invalid archive member size') from exc
        body_start = position + AR_HEADER_SIZE
        body_end = body_start + member_size
        if body_end > len(data):
            raise ValueError('archive member exceeds archive size')
        body = data[body_start:body_end]
        name, name_size = _archive_member_name(header, body)
        members.append({
            'old_offset': position,
            'header': header,
            'body': body,
            'name': name,
            'name_size': name_size,
        })
        position = body_end + (member_size & 1)

    trailing = data[position:]
    new_bodies = []
    count = 0
    for member in members:
        body = member['body']
        name_size = member['name_size']
        patched_object, changed = _relabel_macho(body[name_size:],
                                                   target_platform)
        if changed:
            count += 1
            body = body[:name_size] + patched_object
        new_bodies.append(body)

    if count == 0:
        return data, 0

    old_to_new = {}
    new_position = len(AR_MAGIC)
    for member, body in zip(members, new_bodies):
        old_to_new[member['old_offset']] = new_position
        new_position += AR_HEADER_SIZE + len(body) + (len(body) & 1)

    for index, member in enumerate(members):
        if member['name'] in AR_INDEX_NAMES:
            new_bodies[index] = _rewrite_ranlib_index(
                new_bodies[index], member['name_size'], old_to_new)
            if len(new_bodies[index]) != len(member['body']):
                raise ValueError('archive symbol index size changed')

    output = bytearray(AR_MAGIC)
    for member, body in zip(members, new_bodies):
        header = bytearray(member['header'])
        # Darwin's archive readers expect the decimal size followed by spaces.
        size_field = f'{len(body):<10d}'.encode('ascii')
        header[48:58] = size_field
        output.extend(header)
        output.extend(body)
        if len(body) & 1:
            output.append(0)
    output.extend(trailing)
    return bytes(output), count


def _relabel_fat(data, target_platform):
    fat_magic = struct.unpack_from('>I', data, 0)[0]
    is_64 = fat_magic == FAT_MAGIC_64
    nfat = struct.unpack_from('>I', data, 4)[0]
    entry_size = 32 if is_64 else 20
    header_size = 8 + nfat * entry_size
    if header_size > len(data):
        raise ValueError('fat header exceeds binary size')

    entries = []
    patched_slices = []
    total = 0
    for index in range(nfat):
        entry = 8 + index * entry_size
        if is_64:
            cputype, cpusubtype, offset, size, align, reserved = \
                struct.unpack_from('>iiQQII', data, entry)
        else:
            cputype, cpusubtype, offset, size, align = \
                struct.unpack_from('>iiIII', data, entry)
            reserved = None
        if offset + size > len(data):
            raise ValueError('fat slice exceeds binary size')
        slice_data = data[offset:offset + size]
        if cputype == CPU_TYPE_ARM64:
            slice_data, changed = _relabel_archive(slice_data,
                                                    target_platform)
            if not changed and not slice_data.startswith(AR_MAGIC):
                slice_data, changed = _relabel_macho(slice_data,
                                                     target_platform)
            total += changed
        patched_slices.append(slice_data)
        entries.append((cputype, cpusubtype, align, reserved))

    if total == 0:
        return data, 0

    old_end = max(
        struct.unpack_from('>Q' if is_64 else '>I', data,
                           8 + index * entry_size + (8 if is_64 else 8))[0]
        + struct.unpack_from('>Q' if is_64 else '>I', data,
                             8 + index * entry_size + (16 if is_64 else 12))[0]
        for index in range(nfat))
    output = bytearray(data[:header_size])
    new_locations = []
    for slice_data, entry_data in zip(patched_slices, entries):
        align = entry_data[2]
        if align >= 63:
            raise ValueError('fat slice alignment is too large')
        alignment = 1 << align
        new_offset = (len(output) + alignment - 1) & ~(alignment - 1)
        if len(output) < new_offset:
            output.extend(b'\0' * (new_offset - len(output)))
        output.extend(slice_data)
        new_locations.append((new_offset, len(slice_data)))
    output.extend(data[old_end:])

    for index, ((cputype, cpusubtype, align, reserved),
                (new_offset, new_size)) in enumerate(zip(entries, new_locations)):
        entry = 8 + index * entry_size
        if is_64:
            struct.pack_into('>iiQQII', output, entry, cputype, cpusubtype,
                             new_offset, new_size, align, reserved)
        else:
            if new_offset > 0xFFFFFFFF or new_size > 0xFFFFFFFF:
                raise ValueError('fat slice exceeds 32-bit range')
            struct.pack_into('>iiIII', output, entry, cputype, cpusubtype,
                             new_offset, new_size, align)
    return bytes(output), total


def _relabel_buffer(data, target_platform):
    if len(data) < 8:
        return data, 0
    fat_magic = struct.unpack_from('>I', data, 0)[0]
    if fat_magic in (FAT_MAGIC, FAT_MAGIC_64):
        return _relabel_fat(data, target_platform)
    if data.startswith(AR_MAGIC):
        return _relabel_archive(data, target_platform)
    if struct.unpack_from('<I', data, 0)[0] == MH_MAGIC_64:
        return _relabel_macho(data, target_platform)
    return data, 0


def _relabel_file(path, target_platform):
    if os.path.getsize(path) == 0:
        return 0
    with open(path, 'rb') as file:
        original = file.read()
    patched, count = _relabel_buffer(original, target_platform)
    if count == 0:
        return 0

    mode = stat.S_IMODE(os.stat(path).st_mode)
    directory = os.path.dirname(path) or '.'
    descriptor, temporary = tempfile.mkstemp(
        prefix=f'.{os.path.basename(path)}.', suffix='.tmp', dir=directory)
    try:
        with os.fdopen(descriptor, 'wb') as file:
            file.write(patched)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return count


def _find_framework_binary(pod_dir):
    frameworks_dir = os.path.join(pod_dir, 'Frameworks')
    if not os.path.isdir(frameworks_dir):
        return None
    for name in os.listdir(frameworks_dir):
        if name.endswith('.framework'):
            base = name[:-len('.framework')]
            binary = os.path.join(frameworks_dir, name, base)
            if os.path.isfile(binary):
                return binary
    return None


def _iter_framework_binaries(pods_root):
    for pattern in ('MLKit*', 'MLImage*'):
        for pod_dir in sorted(glob.glob(os.path.join(pods_root, pattern))):
            if os.path.isdir(pod_dir):
                binary = _find_framework_binary(pod_dir)
                if binary:
                    yield binary


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', default=os.environ.get('PLATFORM_NAME', ''))
    parser.add_argument('--pods-root', required=True)
    args = parser.parse_args(argv)

    target_platform = PLATFORM_BY_SDK.get(args.platform)
    if target_platform is None:
        print(f'[ml_kit] skipping arm64 relabel: platform {args.platform!r} '
              'is not iphoneos/iphonesimulator', file=sys.stderr)
        return 0

    binaries = list(_iter_framework_binaries(args.pods_root))
    if not binaries:
        print('[ml_kit] ERROR: no ML Kit framework binaries found under '
              f'{args.pods_root!r}; arm64 slice not relabeled', file=sys.stderr)
        return 1

    total = sum(_relabel_file(binary, target_platform) for binary in binaries)
    if total:
        print(f'[ml_kit] relabeled {total} arm64 object(s) for {args.platform}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as exc:
        print(f'[ml_kit] ERROR: arm64 relabel failed: {exc}', file=sys.stderr)
        sys.exit(1)
