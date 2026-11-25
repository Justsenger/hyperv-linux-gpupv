"""Local release-contract and detached Linux module signature tests."""
import json
from pathlib import Path
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from release.bundle import check_elf


def fixture(kind,machine):
    return b"\x7fELF\x02\x01"+bytes(10)+struct.pack("<HH",kind,machine)+bytes(60)


class Contract(unittest.TestCase):
    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux guest CLI")
    def test_prebuilt_symbol_versions(self):
        check = runpy.run_path(str(ROOT/"guest/gpupv-guest"))["prebuilt_abi_mismatch"]
        with tempfile.TemporaryDirectory() as tmp:
            stock = Path(tmp)/"pci-hyperv.ko"
            stock.touch()
            def command(args, **kwargs):
                if args[0] == "modinfo":
                    return subprocess.CompletedProcess(args, 0, str(stock))
                crc = "0x28615977" if args[-1] == str(stock) else "0xa0f12abe"
                return subprocess.CompletedProcess(args, 0, crc + "\tmodule_layout\n")
            with patch("shutil.which", return_value="/sbin/modprobe"), patch("subprocess.run", side_effect=command):
                self.assertIsNone(check(stock))
                self.assertIn("module_layout", check(Path(tmp)/"same-release.ko"))

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux guest CLI")
    def test_adapter_identity(self):
        verify = runpy.run_path(str(ROOT/"guest/gpupv-guest"))["verify_adapter_ids"]
        adreno = {"device": r"ACPI\VEN_QCOM&DEV_0636&SUBSYS_MSWW8280&REV_1823\0"}
        intel = {"device": r"PCI\VEN_8086&DEV_9A49&SUBSYS_12345678\0"}
        arm = "Adapter 4d4f4351:36333630 hardware=1\n"
        pci = "Adapter 8086:9a49 hardware=1\n"
        verify([adreno, intel], pci + arm + "Adapter 1414:008c hardware=0\n")
        verify([adreno, adreno], arm + arm)
        for cards, output in (([adreno], pci), ([adreno], arm + pci),
                              ([adreno, adreno], arm), ([{"device":"unknown"}], arm)):
            with self.assertRaises(RuntimeError):
                verify(cards, output)

    def test_native_matrix(self):
        plan=json.loads(subprocess.check_output([sys.executable,str(ROOT/"tests/container-matrix.py"),"--plan"]))
        for row in plan["include"]:
            self.assertEqual(row["runner"],{"x86_64":"ubuntu-24.04","aarch64":"ubuntu-24.04-arm"}[row["arch"]])
        self.assertEqual([r for r in plan["include"] if r["target"]=="archlinuxarm"],[])

    def test_architectures(self):
        for arch,machine in (("x86_64",62),("aarch64",183)):
            for kind in (1,2,3):
                check_elf(fixture(kind,machine),arch,(kind,))
                with self.assertRaises(ValueError):
                    check_elf(fixture(kind,245-machine),arch,(kind,))

    def test_signed_module(self):
        with tempfile.TemporaryDirectory() as td:
            d=Path(td)
            def run(*args):
                return subprocess.run(list(map(str,args)),cwd=d,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            run("openssl","req","-new","-newkey","rsa:2048","-x509","-nodes","-subj","/CN=fixture","-keyout","key","-out","cert.pem")
            run("openssl","x509","-in","cert.pem","-outform","DER","-out","cert.der")
            original=b"test module bytes"*50
            def verify(path):
                data=path.read_bytes()
                marker=b"~Module signature appended~\n"
                self.assertTrue(data.endswith(marker))
                trailer=data[-len(marker)-12:-len(marker)]
                kind,alg,idtype,sl,kl,length=struct.unpack(">BBBBB3xI",trailer)
                self.assertEqual((kind,alg,idtype,sl,kl),(0,0,2,0,0))
                self.assertEqual(data[:-(len(marker)+12+length)],original)
                (d/"sig").write_bytes(data[len(original):len(original)+length])
                (d/"content").write_bytes(original)
                run("openssl","cms","-verify","-binary","-inform","DER","-in","sig","-content","content","-certfile","cert.pem","-noverify")
            (d/"module").write_bytes(original)
            run(sys.executable,ROOT/"guest/sign-module.py","key","cert.der","module")
            verify(d/"module")
            signfile=next(iter(sorted(Path("/usr/src").glob("linux-*/scripts/sign-file"))),None)
            if signfile:
                (d/"reference").write_bytes(original)
                run(signfile,"sha256","key","cert.der","reference")
                verify(d/"reference")


if __name__=="__main__":
    unittest.main(verbosity=2)
