// metal/include/metal_compat/cuda_runtime.h - the CUDA runtime names the host files use, on Metal.
//
// The HIP build's approach (include/cortex/hip_compat/cuda_runtime.h maps every cudaX the host code calls to hipX),
// applied to Metal: this directory goes first on the Metal build's include path, so the shared host files compile for
// Metal UNCHANGED, and the CUDA / HIP builds never see this file (their objects stay byte-identical by construction).
// Every name forwards to cortex::gpu's Metal implementation (metal/src/gpu/runtime.cpp), whose semantics are the
// CUDA ones.  Only the names in the Phase 1 inventory (phaseA-tests/mac-design.md §1.3) are provided; a host file that
// uses another one fails to compile on Metal, which is the point.
#pragma once

#include <cstddef>
#include <cstdint>

#include <immintrin.h>               // metal_compat/immintrin.h: CUDA's headers bring the x86 one in on a PC
#include "cortex/gpu/runtime.hpp"    // metal/include/cortex/gpu: the Metal runtime

namespace cortex::gpu::compat_detail { inline Error bad() { return kErrorUnsupported; } }

// ---- types and constants
using cudaError_t = cortex::gpu::Error;
using cudaStream_t = cortex::gpu::Stream;
using cudaEvent_t = cortex::gpu::Event;
using cudaGraph_t = cortex::gpu::Graph;
using cudaGraphExec_t = cortex::gpu::GraphExec;
using cudaGraphNode_t = void*;
using cudaDeviceProp = cortex::gpu::DeviceProp;
using cudaMemcpyKind = cortex::gpu::CopyKind;
using cudaHostFn_t = cortex::gpu::HostFn;
inline constexpr cudaError_t cudaSuccess = cortex::gpu::kSuccess;
inline constexpr cudaError_t cudaErrorNotReady = cortex::gpu::kNotReady;
inline constexpr cudaError_t cudaErrorMemoryAllocation = cortex::gpu::kErrorMemoryAllocation;
inline constexpr cudaError_t cudaErrorPeerAccessAlreadyEnabled = cortex::gpu::kErrorPeerAccessAlreadyEnabled;
inline constexpr cudaError_t cudaErrorStreamCaptureUnsupported = cortex::gpu::kErrorUnsupported;
inline constexpr cudaMemcpyKind cudaMemcpyHostToDevice = cortex::gpu::kHostToDevice;
inline constexpr cudaMemcpyKind cudaMemcpyDeviceToHost = cortex::gpu::kDeviceToHost;
inline constexpr cudaMemcpyKind cudaMemcpyDeviceToDevice = cortex::gpu::kDeviceToDevice;
inline constexpr cudaMemcpyKind cudaMemcpyDefault = cortex::gpu::kCopyDefault;
inline constexpr unsigned cudaHostAllocDefault = cortex::gpu::kHostAllocDefault;
inline constexpr unsigned cudaHostAllocPortable = cortex::gpu::kHostAllocPortable;
inline constexpr unsigned cudaHostAllocMapped = cortex::gpu::kHostAllocMapped;
inline constexpr unsigned cudaHostRegisterPortable = cortex::gpu::kHostRegisterPortable;
inline constexpr unsigned cudaHostRegisterMapped = cortex::gpu::kHostRegisterMapped;
inline constexpr unsigned cudaHostRegisterReadOnly = cortex::gpu::kHostRegisterReadOnly;
inline constexpr unsigned cudaEventDefault = cortex::gpu::kEventDefault;
inline constexpr unsigned cudaEventDisableTiming = cortex::gpu::kEventDisableTiming;
inline constexpr unsigned cudaEventBlockingSync = cortex::gpu::kEventBlockingSync;
inline constexpr unsigned cudaStreamNonBlocking = cortex::gpu::kStreamNonBlocking;
enum cudaStreamCaptureMode { cudaStreamCaptureModeGlobal = 0, cudaStreamCaptureModeThreadLocal = 1, cudaStreamCaptureModeRelaxed = 2 };
// (the compute capability is asked by the 0.1.45 Turing defaults in verify.cpp: no answer here, which reads as "not a Turing card")
enum cudaDeviceAttr {
    cudaDevAttrClockRate = 13, cudaDevAttrMultiProcessorCount = 16, cudaDevAttrIntegrated = 18,
    cudaDevAttrComputeCapabilityMajor = 75, cudaDevAttrComputeCapabilityMinor = 76
};

// ---- errors, devices
inline cudaError_t cudaGetLastError() { return cortex::gpu::get_last_error(); }
inline cudaError_t cudaPeekAtLastError() { return cortex::gpu::peek_last_error(); }
inline const char* cudaGetErrorString(cudaError_t e) { return cortex::gpu::error_string(e); }
inline cudaError_t cudaGetDevice(int* d) { return cortex::gpu::get_device(d); }
inline cudaError_t cudaSetDevice(int d) { return cortex::gpu::set_device(d); }
inline cudaError_t cudaGetDeviceCount(int* n) { return cortex::gpu::device_count(n); }
inline cudaError_t cudaDeviceSynchronize() { return cortex::gpu::device_synchronize(); }
inline cudaError_t cudaMemGetInfo(size_t* f, size_t* t) { return cortex::gpu::mem_get_info(f, t); }
inline cudaError_t cudaGetDeviceProperties(cudaDeviceProp* p, int d) { return cortex::gpu::get_device_properties(p, d); }
inline cudaError_t cudaRuntimeGetVersion(int* v) { return cortex::gpu::runtime_version(v); }
inline cudaError_t cudaDriverGetVersion(int* v) { return cortex::gpu::runtime_version(v); }
inline cudaError_t cudaDeviceGetAttribute(int* v, cudaDeviceAttr a, int d) {
    switch (a) {
        case cudaDevAttrIntegrated: return cortex::gpu::device_integrated(v, d);
        case cudaDevAttrMultiProcessorCount: return cortex::gpu::device_sm_count(v, d);
        case cudaDevAttrClockRate: return cortex::gpu::device_clock_khz(v, d);
        case cudaDevAttrComputeCapabilityMajor:
        case cudaDevAttrComputeCapabilityMinor: return cortex::gpu::compat_detail::bad();
    }
    return cortex::gpu::compat_detail::bad();
}
inline cudaError_t cudaDeviceCanAccessPeer(int* v, int d, int p) { return cortex::gpu::device_can_access_peer(v, d, p); }
inline cudaError_t cudaDeviceEnablePeerAccess(int p, unsigned f) { return cortex::gpu::device_enable_peer_access(p, f); }
inline cudaError_t cudaDeviceDisablePeerAccess(int) { return cudaSuccess; }   // a Mac has one GPU: nothing to disable

// ---- memory and copies
template <class T> inline cudaError_t cudaMalloc(T** p, size_t n) { return cortex::gpu::malloc_device(p, n); }
inline cudaError_t cudaFree(void* p) { return cortex::gpu::free_device(p); }
template <class T> inline cudaError_t cudaHostAlloc(T** p, size_t n, unsigned f) { return cortex::gpu::host_alloc(p, n, f); }
template <class T> inline cudaError_t cudaMallocHost(T** p, size_t n) { return cortex::gpu::malloc_host(p, n); }
inline cudaError_t cudaFreeHost(void* p) { return cortex::gpu::free_host(p); }
template <class T> inline cudaError_t cudaHostGetDevicePointer(T** d, void* h, unsigned f) { return cortex::gpu::host_device_pointer(d, h, f); }
inline cudaError_t cudaHostRegister(void* p, size_t n, unsigned f) { return cortex::gpu::host_register(p, n, f); }
inline cudaError_t cudaHostUnregister(void* p) { return cortex::gpu::host_unregister(p); }
inline cudaError_t cudaMemset(void* p, int v, size_t n) { return cortex::gpu::memset_device(p, v, n); }
inline cudaError_t cudaMemsetAsync(void* p, int v, size_t n, cudaStream_t s = nullptr) { return cortex::gpu::memset_async(p, v, n, s); }
inline cudaError_t cudaMemcpy(void* d, const void* s, size_t n, cudaMemcpyKind k) { return cortex::gpu::memcpy_sync(d, s, n, k); }
inline cudaError_t cudaMemcpyAsync(void* d, const void* s, size_t n, cudaMemcpyKind k, cudaStream_t st = nullptr) {
    return cortex::gpu::memcpy_async(d, s, n, k, st);
}
inline cudaError_t cudaMemcpy2DAsync(void* d, size_t dp, const void* s, size_t sp, size_t w, size_t h, cudaMemcpyKind k,
                                     cudaStream_t st = nullptr) {
    return cortex::gpu::memcpy_2d_async(d, dp, s, sp, w, h, k, st);
}
inline cudaError_t cudaMemcpyPeerAsync(void* d, int dd, const void* s, int sd, size_t n, cudaStream_t st = nullptr) {
    return cortex::gpu::memcpy_peer_async(d, dd, s, sd, n, st);
}
inline cudaError_t cudaMemcpyPeer(void* d, int dd, const void* s, int sd, size_t n) {
    const cudaError_t e = cudaMemcpyPeerAsync(d, dd, s, sd, n, nullptr);
    return e != cudaSuccess ? e : cudaDeviceSynchronize();
}

// ---- streams, events, host functions
inline cudaError_t cudaStreamCreate(cudaStream_t* s) { return cortex::gpu::stream_create(s); }
inline cudaError_t cudaStreamCreateWithFlags(cudaStream_t* s, unsigned f) { return cortex::gpu::stream_create(s, f); }
inline cudaError_t cudaDeviceGetStreamPriorityRange(int*, int*) { return cortex::gpu::compat_detail::bad(); }   // no priorities: callers fall back to a plain stream
inline cudaError_t cudaStreamCreateWithPriority(cudaStream_t* s, unsigned f, int) { return cortex::gpu::stream_create(s, f); }
inline cudaError_t cudaStreamDestroy(cudaStream_t s) { return cortex::gpu::stream_destroy(s); }
inline cudaError_t cudaStreamSynchronize(cudaStream_t s) { return cortex::gpu::stream_synchronize(s); }
inline cudaError_t cudaStreamQuery(cudaStream_t s) { return cortex::gpu::stream_query(s); }
inline cudaError_t cudaStreamWaitEvent(cudaStream_t s, cudaEvent_t e, unsigned f = 0) { return cortex::gpu::stream_wait_event(s, e, f); }
inline cudaError_t cudaLaunchHostFunc(cudaStream_t s, cudaHostFn_t fn, void* a) { return cortex::gpu::launch_host_func(s, fn, a); }
inline cudaError_t cudaEventCreate(cudaEvent_t* e) { return cortex::gpu::event_create(e); }
inline cudaError_t cudaEventCreateWithFlags(cudaEvent_t* e, unsigned f) { return cortex::gpu::event_create(e, f); }
inline cudaError_t cudaEventDestroy(cudaEvent_t e) { return cortex::gpu::event_destroy(e); }
inline cudaError_t cudaEventRecord(cudaEvent_t e, cudaStream_t s = nullptr) { return cortex::gpu::event_record(e, s); }
inline cudaError_t cudaEventQuery(cudaEvent_t e) { return cortex::gpu::event_query(e); }
inline cudaError_t cudaEventSynchronize(cudaEvent_t e) { return cortex::gpu::event_synchronize(e); }
inline cudaError_t cudaEventElapsedTime(float* ms, cudaEvent_t a, cudaEvent_t b) { return cortex::gpu::event_elapsed_ms(ms, a, b); }

// ---- graphs
inline cudaError_t cudaStreamBeginCapture(cudaStream_t s, cudaStreamCaptureMode m) {
    return m == cudaStreamCaptureModeThreadLocal ? cortex::gpu::begin_capture(s) : cortex::gpu::compat_detail::bad();
}
inline cudaError_t cudaStreamEndCapture(cudaStream_t s, cudaGraph_t* g) { return cortex::gpu::end_capture(s, g); }
inline cudaError_t cudaGraphGetNodes(cudaGraph_t g, cudaGraphNode_t* nodes, size_t* n) {
    return nodes == nullptr ? cortex::gpu::graph_node_count(g, n) : cortex::gpu::compat_detail::bad();
}
inline cudaError_t cudaGraphInstantiate(cudaGraphExec_t* x, cudaGraph_t g, cudaGraphNode_t*, char*, size_t) {
    return cortex::gpu::graph_instantiate(x, g);
}
inline cudaError_t cudaGraphInstantiate(cudaGraphExec_t* x, cudaGraph_t g, unsigned long long f = 0) {
    return cortex::gpu::graph_instantiate(x, g, f);
}
inline cudaError_t cudaGraphLaunch(cudaGraphExec_t x, cudaStream_t s) { return cortex::gpu::graph_launch(x, s); }
inline cudaError_t cudaGraphUpload(cudaGraphExec_t x, cudaStream_t s) { return cortex::gpu::graph_upload(x, s); }
inline cudaError_t cudaGraphDestroy(cudaGraph_t g) { return cortex::gpu::graph_destroy(g); }
inline cudaError_t cudaGraphExecDestroy(cudaGraphExec_t x) { return cortex::gpu::graph_exec_destroy(x); }
