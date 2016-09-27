#include <cuda.h>
#include <cuda_runtime.h>
#include "common.h"
#include "efficient.h"

namespace StreamCompaction {
namespace Efficient {

// TODO: __global__

/**
 * Performs prefix-sum (aka scan) on idata, storing the result into odata.
 */

int *dev_Data;
int *dev_Flag;
int *dev_ScanResult;
int *dev_OutputData;
int *dev_total;

//__global__ void CudaUpSweep(int d, int *data)
//{
//	int thid = threadIdx.x;
//	int m = 1 << (d + 1);
//	if (!(thid % m))
//		data[thid + m - 1] += data[thid + (m >> 1) - 1];
//}
//
//__global__ void CudaDownSweep(int d, int *data)
//{
//	int thid = threadIdx.x;
//	int m = 1 << (d + 1);
//	if (!(thid % m))
//	{
//		int temp = data[thid + (m >> 1) - 1];
//		data[thid + (m >> 1) - 1] = data[thid + m - 1];
//		data[thid + m - 1] += temp;
//	}
//}
__global__ void CudaUpSweep(int d, int *data)
{
	int thid = threadIdx.x;
	data[(thid + 1) * (1 << (d + 1)) - 1] += data[(thid + 1) * (1 << (d + 1)) - 1 - (1 << d)];
}

__global__ void CudaDownSweep(int d, int *data)
{
	int thid = threadIdx.x;
	int m = (thid + 1) * (1 << (d + 1));
	int temp = data[m - 1 - (1 << d)];
	data[m - 1 - (1 << d)] = data[m - 1];
	data[m - 1] += temp;
}

void scan(int n, int *odata, const int *idata) {
 //   int n = 8;
	//int idata[8] ={0,1,2,3,4,5,6,7};
	//int odata[8];
	int nCeilLog = ilog2ceil(n);
	int nLength = 1 << nCeilLog;

	cudaMalloc((void**)&dev_Data, nLength * sizeof(int));
	checkCUDAError("cudaMalloc failed!");

	cudaMemcpy(dev_Data, idata, sizeof(int) * nLength, cudaMemcpyHostToDevice);
	checkCUDAError("cudaMemcpy to device failed!");

	for (int i = 0; i < nCeilLog; i++)
	{
		int addTimes = 1 << (nCeilLog - 1 - i);
		CudaUpSweep<<<1, addTimes>>>(i, dev_Data);
	}

	cudaMemset(dev_Data + nLength - 1, 0, sizeof(int));
	checkCUDAError("cudaMemset failed!");
	for (int i = nCeilLog - 1; i >= 0; i--)
	{
		int addTimes = 1 << (nCeilLog - 1 - i);
		CudaDownSweep<<<1, addTimes>>>(i, dev_Data);
	}

	cudaMemcpy(odata, dev_Data, sizeof(int) * n, cudaMemcpyDeviceToHost);
	checkCUDAError("cudaMemcpy to host failed!");	
			//	for (int j = 0; j < n; j++)
		//	printf("%d ", odata[j]);
		//printf("\n");
	cudaFree(dev_Data);
}

__global__ void CudaGetFlag(int *out, int *in)
{
	int thid = threadIdx.x;
	out[thid] = in[thid] ? 1 : 0;
}

__global__ void CudaGetResult(int *result, int *flag, int *scanResult, int *data)
{
	int thid = threadIdx.x;
	if (flag[thid])
		result[scanResult[thid]] = data[thid];
}

__global__ void CudaGetTotal(int *total, int *flag)
{
	int thid = threadIdx.x;
	
	if (flag[thid])
	{
		total[0] = total[0] + total[1];
		total[1] = 100;
		printf("%d %d %d\n", thid, flag[thid], total[0]);
	}
}

void test(int *buffer, int size)
{
	int *cao = new int[size];
	cudaMemcpy(cao, buffer, sizeof(int) * size, cudaMemcpyDeviceToHost);
	checkCUDAError("cudaMemcpy to host failed!");

	for (int i = 0; i < size; i++)
		printf("%d ", cao[i]);
	printf("\n");
	delete [] cao;
}
/**
 * Performs stream compaction on idata, storing the result into odata.
 * All zeroes are discarded.
 *
 * @param n      The number of elements in idata.
 * @param odata  The array into which to store elements.
 * @param idata  The array of elements to compact.
 * @returns      The number of elements remaining after compaction.
 */
int compact(int n, int *odata, const int *idata) {
    // TODO
	if (n <= 0)
		return -1;
	
	int nCeilLog = ilog2ceil(n);
	int nLength = 1 << nCeilLog;

	cudaMalloc((void**)&dev_Data, nLength * sizeof(int));
	cudaMalloc((void**)&dev_ScanResult, nLength * sizeof(int));
	cudaMalloc((void**)&dev_Flag, nLength * sizeof(int));
	cudaMalloc((void**)&dev_OutputData, n * sizeof(int));
	checkCUDAError("cudaMalloc failed!");

	cudaMemcpy(dev_Data, idata, nLength * sizeof(int), cudaMemcpyHostToDevice);
	checkCUDAError("cudaMemcpy to device failed!");

	// dev_Flag is 0 or 1, calculate dev_Flag
	CudaGetFlag<<<1, nLength>>>(dev_Flag, dev_Data);

	// now scan
	cudaMemcpy(dev_ScanResult, dev_Flag, nLength * sizeof(int), cudaMemcpyDeviceToDevice);
	checkCUDAError("cudaMemcpy device to device failed!");
	for (int i = 0; i < nCeilLog; i++)
	{
		int addTimes = 1 << (nCeilLog - 1 - i);
		CudaUpSweep<<<1, addTimes>>>(i, dev_ScanResult);
	}
	cudaMemset(dev_ScanResult + nLength - 1, 0, sizeof(int));
	checkCUDAError("cudaMemcpy to device failed!");
	for (int i = nCeilLog - 1; i >= 0; i--)
	{
		int addTimes = 1 << (nCeilLog - 1 - i);
		CudaDownSweep<<<1, addTimes>>>(i, dev_ScanResult);
	}

	CudaGetResult<<<1, n>>>(dev_OutputData, dev_Flag, dev_ScanResult, dev_Data);
	cudaMemcpy(odata, dev_OutputData, sizeof(int) * n, cudaMemcpyDeviceToHost);
	checkCUDAError("cudaMemcpy to host failed!");	
	
	int total, flag;
	cudaMemcpy(&total, dev_ScanResult + n - 1, sizeof(int), cudaMemcpyDeviceToHost);
	cudaMemcpy(&flag, dev_Flag + n - 1, sizeof(int), cudaMemcpyDeviceToHost);
	checkCUDAError("cudaMemcpy device to device failed!");
	
	cudaFree(dev_Data);
	cudaFree(dev_ScanResult);
	cudaFree(dev_Flag);
	cudaFree(dev_OutputData);

	return flag ? total + 1 : total;
}

}
}
