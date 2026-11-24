// SPDX-License-Identifier: MIT
#include <wsl/winadapter.h>
#include <directx/dxcore.h>
#include <directx/d3d12.h>
#include <dlfcn.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <thread>

template<class T> struct Com {
    T *p = nullptr;
    Com() = default;
    Com(const Com&) = delete;
    ~Com() { if (p) p->Release(); }
    T *operator->() const { return p; }
};

static void check(HRESULT result, const char *call) {
    std::printf("%s HRESULT=0x%08x\n", call, unsigned(result));
    if (FAILED(result)) throw std::runtime_error(call);
}
static void *library(const char *name) {
    void *lib = dlopen(name, RTLD_NOW | RTLD_LOCAL);
    if (!lib) throw std::runtime_error(dlerror());
    return lib;
}
template<class T> static T symbol(void *lib, const char *name) {
    void *fn = dlsym(lib,name);
    if (!fn) throw std::runtime_error(dlerror());
    return reinterpret_cast<T>(fn);
}
static void compute(ID3D12Device *device, void *runtime) {
    static const unsigned char shader[] = {
#include "intel-compute.inc"
    };
    D3D12_ROOT_PARAMETER parameter{};
    parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV;
    parameter.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
    D3D12_ROOT_SIGNATURE_DESC rootDesc{};
    rootDesc.NumParameters = 1;
    rootDesc.pParameters = &parameter;
    Com<ID3DBlob> rootBlob, errors;
    auto serialize = symbol<PFN_D3D12_SERIALIZE_ROOT_SIGNATURE>(runtime,"D3D12SerializeRootSignature");
    check(serialize(&rootDesc,D3D_ROOT_SIGNATURE_VERSION_1,&rootBlob.p,&errors.p),"SerializeRootSignature");
    Com<ID3D12RootSignature> root;
    check(device->CreateRootSignature(0,rootBlob->GetBufferPointer(),rootBlob->GetBufferSize(),IID_ID3D12RootSignature,reinterpret_cast<void **>(&root.p)),"CreateRootSignature");
    D3D12_COMPUTE_PIPELINE_STATE_DESC pipelineDesc{};
    pipelineDesc.pRootSignature = root.p;
    pipelineDesc.CS = {shader,sizeof(shader)};
    Com<ID3D12PipelineState> pipeline;
    check(device->CreateComputePipelineState(&pipelineDesc,IID_ID3D12PipelineState,reinterpret_cast<void **>(&pipeline.p)),"CreateComputePipelineState");
    D3D12_COMMAND_QUEUE_DESC q{};
    q.Type = D3D12_COMMAND_LIST_TYPE_COMPUTE;
    Com<ID3D12CommandQueue> queue;
    Com<ID3D12CommandAllocator> allocator;
    Com<ID3D12GraphicsCommandList> list;
    check(device->CreateCommandQueue(&q,IID_ID3D12CommandQueue,reinterpret_cast<void **>(&queue.p)),"CreateCommandQueue");
    check(device->CreateCommandAllocator(q.Type,IID_ID3D12CommandAllocator,reinterpret_cast<void **>(&allocator.p)),"CreateCommandAllocator");
    check(device->CreateCommandList(0,q.Type,allocator.p,pipeline.p,IID_ID3D12GraphicsCommandList,reinterpret_cast<void **>(&list.p)),"CreateCommandList");
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    heap.CreationNodeMask = heap.VisibleNodeMask = 1;
    D3D12_RESOURCE_DESC desc{};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    desc.Width = 64*sizeof(uint32_t);
    desc.Height = desc.DepthOrArraySize = desc.MipLevels = desc.SampleDesc.Count = 1;
    desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
    Com<ID3D12Resource> output, readback;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_UNORDERED_ACCESS,nullptr,IID_ID3D12Resource,reinterpret_cast<void **>(&output.p)),"CreateOutput");
    heap.Type = D3D12_HEAP_TYPE_READBACK;
    desc.Flags = D3D12_RESOURCE_FLAG_NONE;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_ID3D12Resource,reinterpret_cast<void **>(&readback.p)),"CreateReadback");
    list->SetComputeRootSignature(root.p);
    list->SetComputeRootUnorderedAccessView(0,output->GetGPUVirtualAddress());
    list->Dispatch(1,1,1);
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = output.p;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    list->ResourceBarrier(1,&barrier);
    list->CopyBufferRegion(readback.p,0,output.p,0,desc.Width);
    check(list->Close(),"Close");
    Com<ID3D12Fence> fence;
    check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_ID3D12Fence,reinterpret_cast<void **>(&fence.p)),"CreateFence");
    ID3D12CommandList *commands[] = {list.p};
    queue->ExecuteCommandLists(1,commands);
    check(queue->Signal(fence.p,1),"Signal");
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
    while (fence->GetCompletedValue()==0 && std::chrono::steady_clock::now()<deadline)
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    if (fence->GetCompletedValue()!=1) throw std::runtime_error("Fence timeout or device removed");
    void *data=nullptr;
    D3D12_RANGE range{0,static_cast<SIZE_T>(desc.Width)};
    check(readback->Map(0,&range,&data),"Map");
    auto values=static_cast<const uint32_t*>(data);
    bool valid=true;
    for (unsigned i=0;i<64;i++) valid &= values[i]==7*i+3;
    std::printf("Dispatch readback: [0]=%u [31]=%u [63]=%u matched=%s\n",values[0],values[31],values[63],valid?"64/64":"no");
    D3D12_RANGE written{0,0};
    readback->Unmap(0,&written);
    if (!valid) throw std::runtime_error("Compute result mismatch");
}

int main() {
    try {
        void *core=library("libdxcore.so"), *runtime=library("libd3d12.so");
        using FactoryFn=HRESULT (*)(REFIID,void **);
        auto create=symbol<FactoryFn>(core,"DXCoreCreateAdapterFactory");
        auto deviceFn=symbol<PFN_D3D12_CREATE_DEVICE>(runtime,"D3D12CreateDevice");
        Com<IDXCoreAdapterFactory> factory;
        check(create(IID_IDXCoreAdapterFactory,reinterpret_cast<void **>(&factory.p)),"DXCoreCreateAdapterFactory");
        Com<IDXCoreAdapterList> adapters;
        check(factory->CreateAdapterList(1,&DXCORE_ADAPTER_ATTRIBUTE_D3D12_CORE_COMPUTE,IID_IDXCoreAdapterList,reinterpret_cast<void **>(&adapters.p)),"CreateAdapterList(CORE_COMPUTE)");
        std::printf("Adapter count=%u\n",adapters->GetAdapterCount());
        unsigned verified=0;
        for(unsigned i=0;i<adapters->GetAdapterCount();i++){
            Com<IDXCoreAdapter> adapter;
            check(adapters->GetAdapter(i,IID_IDXCoreAdapter,reinterpret_cast<void **>(&adapter.p)),"GetAdapter");
            DXCoreHardwareID id{};
            bool hardware=false;
            check(adapter->GetProperty(DXCoreAdapterProperty::HardwareID,&id),"HardwareID");
            check(adapter->GetProperty(DXCoreAdapterProperty::IsHardware,&hardware),"IsHardware");
            std::printf("Adapter %04x:%04x hardware=%u\n",id.vendorID,id.deviceID,unsigned(hardware));
            if(!hardware) continue;
            Com<ID3D12Device> device;
            check(deviceFn(adapter.p,D3D_FEATURE_LEVEL_11_0,IID_ID3D12Device,reinterpret_cast<void **>(&device.p)),"D3D12CreateDevice");
            compute(device.p,runtime);
            ++verified;
        }
        if (!verified) throw std::runtime_error("No hardware compute adapter");
        std::printf("Verified hardware adapters=%u\n",verified);
        return 0;
    } catch(const std::exception &e) { std::fprintf(stderr,"%s\n",e.what()); return 1; }
}
