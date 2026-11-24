RWStructuredBuffer<uint> result : register(u0);
[numthreads(64, 1, 1)]
void main(uint3 thread : SV_DispatchThreadID)
{
    result[thread.x] = thread.x * 7 + 3;
}
