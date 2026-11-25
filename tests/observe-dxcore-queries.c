/* ELF64 glibc PLT observer for an ordinary opt-in test process. */
#define _GNU_SOURCE
#include <link.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/uio.h>
#include <sys/ioctl.h>

unsigned int la_version(unsigned int v) { return v < LAV_CURRENT ? v : LAV_CURRENT; }
unsigned int la_objopen(struct link_map *map, Lmid_t ns, uintptr_t *cookie) {
    (void)ns;
    *cookie = (uintptr_t)map;
    if (strstr(map->l_name, "libdxcore.so"))
        return LA_FLG_BINDFROM;
    return strstr(map->l_name, "libc.so.6") ? LA_FLG_BINDTO : 0;
}
static int read_self(uintptr_t address, void *out, size_t length) {
    struct iovec remote={(void *)address,length}, local={out,length};
    return process_vm_readv(getpid(),&local,1,&remote,1,0)==(ssize_t)length;
}
static void record_failed_request(unsigned long req,uintptr_t arg) {
    if (_IOC_TYPE(req)!=0x47) return;
    unsigned int nr=_IOC_NR(req), words[8]={0};
    size_t size=_IOC_SIZE(req);
    if (size>sizeof(words) || size<8 || !read_self(arg,words,size)) return;
    if (nr==0x49) {
        dprintf(2,"dxcore feature_failed adapter=%#x feature=%u\n",words[0],words[1]);
    } else if (nr==0xd && size==32) {
        dprintf(2,"dxcore escape_failed adapter=%#x device=%#x type=%u flags=%#x size=%u\n",
                words[0],words[1],words[2],words[3],words[6]);
    } else if (nr==9 && size==24) {
        uintptr_t buf;
        memcpy(&buf,&words[2],sizeof(buf));
        unsigned int detail[2];
        if(words[4]<8 || !read_self(buf,detail,sizeof(detail))) return;
        dprintf(2,"dxcore query_failed type=%u bytes=%u",words[1],words[4]);
        if(words[1]==1) dprintf(2," KMTUMDVERSION=%u",detail[0]);
        if(words[1]==48 && words[4]>=528) {
            uint16_t wide[260];
            char name[261]={0};
            if(read_self(buf+8,wide,sizeof(wide))) {
                for(size_t j=0;j<260 && wide[j];++j)
                    name[j]=(wide[j]>=32 && wide[j]<=126)?wide[j]:'?';
            }
            dprintf(2," query_type=%u flags=%#x ValueName=%s",detail[0],detail[1],name);
        }
        dprintf(2,"\n");
    }
}
static int (*libc_ioctl)(int,unsigned long,...);
static void record_handle_change(unsigned long request,uintptr_t arg) {
    unsigned int handle;
    unsigned int nr=_IOC_NR(request);
    if (_IOC_TYPE(request)!=0x47) return;
    if (nr==0x01 && _IOC_SIZE(request)==12 && read_self(arg+8,&handle,sizeof(handle))) {
        dprintf(2,"dxcore open_adapter handle=%#x\n",handle);
    } else if (nr==0x15 && _IOC_SIZE(request)==4 && read_self(arg,&handle,sizeof(handle))) {
        dprintf(2,"dxcore close_adapter handle=%#x\n",handle);
    } else if ((nr==0x14 && _IOC_SIZE(request)==16) || (nr==0x3e && _IOC_SIZE(request)==24)) {
        unsigned int count;
        uintptr_t list;
        size_t offset=nr==0x14?0:8;
        if(read_self(arg+offset,&count,sizeof(count)) && count==1 &&
           read_self(arg+offset+8,&list,sizeof(list)) && list && read_self(list,&handle,sizeof(handle)))
            dprintf(2,"dxcore enumerated_adapter handle=%#x\n",handle);
    }
}
static int observe_ioctl(int fd,unsigned long request,void *argument) {
    int result=libc_ioctl(fd,request,argument);
    int saved=errno;
    if(result<0)
        record_failed_request(request,(uintptr_t)argument);
    else
        record_handle_change(request,(uintptr_t)argument);
    errno=saved;
    return result;
}
uintptr_t la_symbind64(Elf64_Sym *s,unsigned int idx,uintptr_t *from,uintptr_t *to,
                       unsigned int *flags,const char *name) {
    *flags |= LA_SYMB_NOPLTENTER | LA_SYMB_NOPLTEXIT;
    struct link_map *caller=(void *)*from, *provider=(void *)*to;
    if (!strcmp(name,"ioctl") && strstr(caller->l_name,"libdxcore.so") &&
        strstr(provider->l_name,"libc.so.6")) {
        libc_ioctl=(void *)s->st_value;
        dprintf(2,"dxcore ioctl observer bound in ordinary guest process\n");
        return (uintptr_t)observe_ioctl;
    }
    return s->st_value;
}
