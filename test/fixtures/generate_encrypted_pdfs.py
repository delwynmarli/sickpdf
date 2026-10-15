"""Generate synthetic blank PDFs; no private documents or third-party fixtures.

PDF standard security handler revision 2 exercises empty-user-password encryption
versus a required user password. This legacy cipher is for test fixtures only.
Run from the project root with Python's standard library.
"""
import hashlib
from pathlib import Path
import struct

PADDING = bytes.fromhex(
    '28bf4e5e4e758a4164004e56fffa01082e2e00b6d0683e802f0ca9fe6453697a'
)


def padded(password):
    return (password.encode() + PADDING)[:32]


def rc4(data, key):
    state = list(range(256))
    j = 0
    for i in range(256):
        j = (j + state[i] + key[i % len(key)]) % 256
        state[i], state[j] = state[j], state[i]
    i = j = 0
    output = bytearray()
    for value in data:
        i = (i + 1) % 256
        j = (j + state[i]) % 256
        state[i], state[j] = state[j], state[i]
        output.append(value ^ state[(state[i] + state[j]) % 256])
    return bytes(output)


def generate(password):
    identifier = hashlib.md5(b'sickpdf synthetic encryption regression').digest()
    owner = rc4(padded(password), hashlib.md5(padded('owner')).digest()[:5])
    key = hashlib.md5(
        padded(password) + owner + struct.pack('<i', -4) + identifier
    ).digest()[:5]
    user = rc4(PADDING, key)
    objects = [
        '<< /Type /Catalog /Pages 2 0 R >>',
        '<< /Type /Pages /Kids [' + ' '.join(f'{i + 3} 0 R' for i in range(10))
        + '] /Count 10 >>',
        *[f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {200 + i} 300] >>'
          for i in range(10)],
        f'<< /Filter /Standard /V 1 /R 2 /Length 40 /O <{owner.hex()}> '
        f'/U <{user.hex()}> /P -4 >>',
    ]
    data = bytearray(b'%PDF-1.4\n')
    offsets = []
    for index, obj in enumerate(objects):
        offsets.append(len(data))
        data.extend(f'{index + 1} 0 obj\n{obj}\nendobj\n'.encode())
    xref = len(data)
    data.extend(f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode())
    for offset in offsets:
        data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(
        (f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R /Encrypt 13 0 R '
         f'/ID [<{identifier.hex()}><{identifier.hex()}>] >>\n'
         f'startxref\n{xref}\n%%EOF\n').encode()
    )
    return data


if __name__ == '__main__':
    directory = Path(__file__).parent
    (directory / 'owner_encrypted.pdf').write_bytes(generate(''))
    (directory / 'password_required.pdf').write_bytes(generate('secret'))
    print('Generated synthetic encrypted fixtures (10 blank pages each).')
