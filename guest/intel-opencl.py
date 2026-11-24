"""Compute and read back a vector on each enumerated OpenCL GPU."""
import ctypes as c
import sys

P = c.c_void_p
U = c.c_uint32
L = c.c_uint64
I = c.c_int32
Z = c.c_size_t


def bind(lib, name, result, *args):
    fn = getattr(lib, name)
    fn.argtypes = args
    fn.restype = result
    return fn


def check(rc):
    if rc:
        raise RuntimeError(f"OpenCL returned {rc}")


def main():
    lib = c.CDLL("libOpenCL.so.1")
    platforms = bind(lib,"clGetPlatformIDs",I,U,P,P)
    devices = bind(lib,"clGetDeviceIDs",I,P,L,U,P,P)
    info = bind(lib,"clGetDeviceInfo",I,P,U,Z,P,P)
    n = U()
    rc = platforms(0,None,c.byref(n))
    if rc == -1001:
        sys.exit(77)
    check(rc)
    ids = (P*n.value)()
    check(platforms(n,ids,None))
    candidates = []
    for platform in ids:
        rc = devices(platform,4,0,None,c.byref(n))  # CL_DEVICE_TYPE_GPU
        if rc == -1:
            continue
        check(rc)
        gpus = (P*n.value)()
        check(devices(platform,4,n,gpus,None))
        for gpu in gpus:
            vendor = U()
            name = c.create_string_buffer(1024)
            check(info(gpu,0x1001,c.sizeof(vendor),c.byref(vendor),None))
            check(info(gpu,0x102B,len(name),name,None))
            candidates.append((gpu,name.value.decode()))
    if not candidates:
        sys.exit(77)
    for gpu,name in candidates:
        compute(lib,gpu,name)


def compute(lib,gpu,name):
    print("OpenCL GPU:",name,flush=True)
    status = I()
    release = []
    def create(kind, fn, signature, *args):
        handle = bind(lib,fn,P,*signature,P)(*args,c.byref(status))
        check(status.value)
        if not handle:
            raise RuntimeError(f"{fn} returned no handle")
        release.append((bind(lib,"clRelease"+kind,I,P),handle))
        return handle
    try:
        context = create("Context","clCreateContext",[P,U,P,P,P],None,1,c.byref(P(gpu)),None,None)
        queue = create("CommandQueue","clCreateCommandQueue",[P,P,L],context,gpu,0)
        code = c.c_char_p(b"__kernel void transform(__global uint *v){uint i=get_global_id(0); v[i]=v[i]*7u+3u;}")
        program = create("Program","clCreateProgramWithSource",[P,U,P,P],context,1,c.byref(code),None)
        check(bind(lib,"clBuildProgram",I,P,U,P,P,P,P)(program,1,c.byref(P(gpu)),None,None,None))
        kernel = create("Kernel","clCreateKernel",[P,c.c_char_p],program,b"transform")
        count = 32
        values = (U*count)(*range(count))
        buf = create("MemObject","clCreateBuffer",[P,L,Z,P],context,1|32,c.sizeof(values),values)
        check(bind(lib,"clSetKernelArg",I,P,U,Z,P)(kernel,0,c.sizeof(P),c.byref(P(buf))))
        check(bind(lib,"clEnqueueNDRangeKernel",I,P,P,U,P,P,P,U,P,P)(
            queue,kernel,1,None,c.byref(Z(count)),None,0,None,None))
        check(bind(lib,"clEnqueueReadBuffer",I,P,P,U,Z,Z,P,U,P,P)(
            queue,buf,1,0,c.sizeof(values),values,0,None,None))
        if list(values) != [i*7+3 for i in range(count)]:
            raise RuntimeError("Kernel produced incorrect values")
        print(f"{name}: verified {count} OpenCL results, last={values[-1]}")
    finally:
        for fn,handle in reversed(release):
            fn(handle)


if __name__=="__main__":
    try:
        main()
    except (RuntimeError,OSError) as e:
        sys.exit(str(e))

