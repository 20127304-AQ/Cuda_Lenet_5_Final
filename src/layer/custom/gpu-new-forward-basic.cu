#include <cmath>
#include <iostream>
#include "gpu-new-forward.h"


#define TILE_WIDTH 16

#define CHECK(call)\
{\
    const cudaError_t error = call;\
    if (error != cudaSuccess)\
    {\
        fprintf(stderr, "Error: %s:%d, ", __FILE__, __LINE__);\
        fprintf(stderr, "code: %d, reason: %s\n", error,\
                cudaGetErrorString(error));\
        exit(EXIT_FAILURE);\
    }\
}

__global__ void conv_forward_kernel(float *y, const float *x, const float *k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]

    int H_grid = ceil(float(H_out) / TILE_WIDTH);
    int W_grid = ceil(float(W_out) / TILE_WIDTH); 
    
    int b = blockIdx.x;                 // batch number
    int m = blockIdx.y;                 // output feature
    int h = (blockIdx.z / W_grid) * TILE_WIDTH + threadIdx.y; // row of the image matrix
    int w = (blockIdx.z % W_grid) * TILE_WIDTH + threadIdx.x; // col of the image matrix
    
    float sum = 0.0f;

    if (h < H_out && w < W_out) 
    {
        for(int c=0; c<C; c++)             // sum over all input features
        {
            for(int p=0; p<K; p++)         // KxK filter 
                for(int q=0; q<K; q++)
                    sum += x4d(b, c, h+p, w+q) * k4d(m, c, p, q); // 4 dimensions macro resolve thread index
        }
        y4d(b,m,h,w) = sum;
    }

    #undef y4d
    #undef x4d
    #undef k4d
}


	
__host__ void GPUInterface::conv_forward_gpu_prolog(const float *host_y, const float *host_x, const float *host_k, float **device_y_ptr, float **device_x_ptr, float **device_k_ptr, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Allocate memory and copy over the relevant data structures to the GPU

    // We pass double pointers for you to initialize the relevant device pointers,
    //  which are passed to the other two functions.

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int inputSize  = B * C * H * W * sizeof(float);  // input features map is C
    int outputSize = B * M * H_out * W_out * sizeof(float); // output feature map is M
    int maskSize = M * C * K * K * sizeof(float); // C * M filter Maps of size K*K

    CHECK(cudaMalloc((void **) device_x_ptr, inputSize));
    CHECK(cudaMalloc((void **) device_y_ptr, outputSize));
    CHECK(cudaMalloc((void **) device_k_ptr, maskSize));

    // Copy Inout data to device
    CHECK(cudaMemcpy(*device_x_ptr, host_x, inputSize, cudaMemcpyHostToDevice));
    // Copy Mask data to device
    CHECK(cudaMemcpy(*device_k_ptr, host_k, maskSize, cudaMemcpyHostToDevice));

}


__host__ void GPUInterface::conv_forward_gpu(float *device_y, const float *device_x, const float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Set the kernel dimensions and call the kernel
    std::cout << "Basic" << std::endl;

    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int H_grid = ceil(float(H_out) / TILE_WIDTH);
    int W_grid = ceil(float(W_out) / TILE_WIDTH);
    int Z = H_grid * W_grid;

    // Block size
    dim3 blockSize(TILE_WIDTH, TILE_WIDTH, 1);

    // Grid size
    dim3 gridSize(B, M, Z);


    //launch the kernel
    conv_forward_kernel<<<gridSize, blockSize>>>(device_y, device_x, device_k, B, M, C, H, W, K);
}


__host__ void GPUInterface::conv_forward_gpu_epilog(float *host_y, float *device_y, float *device_x, float *device_k, const int B, const int M, const int C, const int H, const int W, const int K)
{
    // Copy the output back to host
    
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int outputSize = B * M * H_out * W_out * sizeof(float);

    CHECK(cudaMemcpy(host_y, device_y, outputSize, cudaMemcpyDeviceToHost));

    // Free device memory
    CHECK(cudaFree(device_x));
    CHECK(cudaFree(device_y));
    CHECK(cudaFree(device_k));
}


__host__ void GPUInterface::get_device_properties()
{
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);

    for(int dev = 0; dev < deviceCount; dev++)
    {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, dev);

        std::cout<<"Device "<<dev<<" name: "<<deviceProp.name<<std::endl;
        std::cout<<"Computational capabilities: "<<deviceProp.major<<"."<<deviceProp.minor<<std::endl;
        std::cout<<"Max Global memory size: "<<deviceProp.totalGlobalMem<<std::endl;
        std::cout<<"Max Constant memory size: "<<deviceProp.totalConstMem<<std::endl;
        std::cout<<"Max Shared memory size per block: "<<deviceProp.sharedMemPerBlock<<std::endl;
        std::cout<<"Max threads per block: "<<deviceProp.maxThreadsPerBlock<<std::endl;
        std::cout<<"Max block dimensions: "<<deviceProp.maxThreadsDim[0]<<" x, "<<deviceProp.maxThreadsDim[1]<<" y, "<<deviceProp.maxThreadsDim[2]<<" z"<<std::endl;
        std::cout<<"Max grid dimensions: "<<deviceProp.maxGridSize[0]<<" x, "<<deviceProp.maxGridSize[1]<<" y, "<<deviceProp.maxGridSize[2]<<" z"<<std::endl;
        std::cout<<"Warp Size: "<<deviceProp.warpSize<<std::endl;
    }
}
