// SPDX-License-Identifier: MIT
// Build on Linux with the distribution's DirectX-Headers development package.
#include <wsl/winadapter.h>
#include <directx/dxcore.h>
#include <directx/d3d12.h>
#include <dlfcn.h>
#include <cstdio>
#include <vector>

int main() {
    void *core = dlopen("libdxcore.so", RTLD_NOW);
    void *runtime = dlopen("libd3d12.so", RTLD_NOW);
    if (!core || !runtime) {
        std::fprintf(stderr, "DirectX runtime load failed: %s\n", dlerror());
        return 1;
    }
    using CreateFactory = HRESULT (*)(REFIID, void **);
    auto factory_fn = reinterpret_cast<CreateFactory>(dlsym(core, "DXCoreCreateAdapterFactory"));
    auto device_fn = reinterpret_cast<PFN_D3D12_CREATE_DEVICE>(dlsym(runtime, "D3D12CreateDevice"));
    if (!factory_fn || !device_fn) return 1;
    IDXCoreAdapterFactory *factory = nullptr;
    HRESULT hr = factory_fn(IID_IDXCoreAdapterFactory, reinterpret_cast<void **>(&factory));
    std::printf("DXCoreCreateAdapterFactory = 0x%08x\n", unsigned(hr));
    if (FAILED(hr)) return 1;
    IDXCoreAdapterList *list = nullptr;
    hr = factory->CreateAdapterList(1, &DXCORE_ADAPTER_ATTRIBUTE_D3D12_GRAPHICS, IID_IDXCoreAdapterList, reinterpret_cast<void **>(&list));
    std::printf("CreateAdapterList(D3D12_GRAPHICS) = 0x%08x\n", unsigned(hr));
    if (FAILED(hr)) return 1;
    unsigned count = list->GetAdapterCount();
    std::printf("Adapter count = %u\n", count);
    bool intel_device = false;
    for (unsigned i = 0; i < count; ++i) {
        IDXCoreAdapter *adapter = nullptr;
        if (FAILED(list->GetAdapter(i, IID_IDXCoreAdapter, reinterpret_cast<void **>(&adapter)))) return 1;
        DXCoreHardwareID id{};
        bool hardware = false;
        size_t size = 0;
        if (FAILED(adapter->GetProperty(DXCoreAdapterProperty::HardwareID, &id)) ||
            FAILED(adapter->GetProperty(DXCoreAdapterProperty::IsHardware, &hardware)) ||
            FAILED(adapter->GetPropertySize(DXCoreAdapterProperty::DriverDescription, &size)) ||
            size > 65536) return 1;
        std::vector<char> description(size + 1);
        if (FAILED(adapter->GetProperty(DXCoreAdapterProperty::DriverDescription, size, description.data()))) return 1;
        std::printf("Adapter %u: %04x:%04x hardware=%d %s\n", i, id.vendorID, id.deviceID, hardware, description.data());
        if (hardware && id.vendorID == 0x8086) {
            ID3D12Device *device = nullptr;
            hr = device_fn(adapter, D3D_FEATURE_LEVEL_11_0, IID_ID3D12Device, reinterpret_cast<void **>(&device));
            std::printf("D3D12CreateDevice(11_0) = 0x%08x\n", unsigned(hr));
            if (SUCCEEDED(hr) && device) {
                intel_device = true;
                device->Release();
            }
        }
        adapter->Release();
    }
    list->Release();
    factory->Release();
    return intel_device ? 0 : 1;
}

