"""Append a detached DER CMS signature in the Linux module_signature format."""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

MAGIC = b"~Module signature appended~\n"


def sign(key, certificate, module):
    module = Path(module)
    with tempfile.TemporaryDirectory(dir=str(module.parent)) as directory:
        pem = Path(directory) / "certificate.pem"
        subprocess.run(["openssl", "x509", "-inform", "DER", "-in", str(certificate),
                        "-out", str(pem)], check=True)
        sig = subprocess.check_output(["openssl", "cms", "-sign", "-binary", "-noattr",
                                      "-nocerts", "-nosmimecap", "-md", "sha256",
                                      "-in", str(module), "-signer", str(pem),
                                      "-inkey", str(key), "-outform", "DER"])
        output = Path(directory) / "signed.ko"
        shutil.copy2(module, output)
        with output.open("ab") as stream:
            stream.write(sig)
            stream.write(struct.pack(">BBBBB3xI", 0, 0, 2, 0, 0, len(sig)))
            stream.write(MAGIC)
        os.replace(output, module)


if __name__ == "__main__":
    sign(*sys.argv[1:])
