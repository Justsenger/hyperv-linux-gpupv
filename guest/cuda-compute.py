"""Submit one PTX kernel to the selected physical device using libcuda."""
import ctypes as c
import sys

lib = c.CDLL("libcuda.so.1")
ptr = c.c_void_p
integer = c.c_int
u64 = c.c_uint64
ref = c.byref


def call(name, types, *args):
    fn = getattr(lib, name)
    fn.argtypes = types
    fn.restype = integer
    status = fn(*args)
    if status:
        raise RuntimeError(f"{name} failed with CUresult {status}")


def main(expected):
    call("cuInit", [c.c_uint], 0)
    count = integer()
    call("cuDeviceGetCount", [ptr], ref(count))
    matches = []
    for ordinal in range(count.value):
        dev = integer()
        call("cuDeviceGet", [ptr,integer], ref(dev),ordinal)
        name = c.create_string_buffer(256)
        call("cuDeviceGetName",[ptr,integer,integer], name,256,dev)
        if expected is None or name.value.decode().casefold() == expected.casefold():
            matches.append((dev,name.value.decode()))
    if not matches:
        raise RuntimeError(f"Cannot identify unique CUDA device {expected}")
    for dev,label in matches:
        compute(dev,label)


def compute(dev,expected):
    ctx = ptr()
    module = ptr()
    function = ptr()
    buf = u64()
    call("cuCtxCreate_v2",[ptr,c.c_uint,integer],ref(ctx),0,dev)
    try:
        ptx = b""".version 6.0
.target sm_50
.address_size 64
.visible .entry transform(.param .u64 dest) {
.reg .b32 r;
.reg .b64 p;
ld.param.u64 p, [dest];
ld.global.u32 r, [p];
mad.lo.u32 r, r, 7, 3;
st.global.u32 [p], r;
ret;
}"""
        call("cuModuleLoadData",[ptr,c.c_char_p],ref(module),ptx)
        call("cuModuleGetFunction",[ptr,ptr,c.c_char_p],ref(function),module,b"transform")
        call("cuMemAlloc_v2",[ptr,c.c_size_t],ref(buf),4)
        args = (ptr*1)(c.cast(ref(buf),ptr))
        for value in (5,19,127):
            result = c.c_uint32(value)
            call("cuMemcpyHtoD_v2",[u64,ptr,c.c_size_t],buf,ref(result),4)
            call("cuLaunchKernel",[ptr]+[c.c_uint]*7+[ptr,ptr,ptr],function,1,1,1,1,1,1,0,None,args,None)
            call("cuCtxSynchronize",[])
            call("cuMemcpyDtoH_v2",[ptr,u64,c.c_size_t],ref(result),buf,4)
            if result.value != 7*value+3:
                raise RuntimeError(f"Wrong CUDA result {result.value}")
            print(f"{expected}: 7 * {value} + 3 = {result.value}")
    finally:
        call("cuCtxDestroy_v2",[ptr],ctx)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv)>1 else None)

