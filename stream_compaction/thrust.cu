#include <cuda.h>
#include <cuda_runtime.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/scan.h>
#include "common.h"
#include "thrust.h"
#include <chrono>

namespace StreamCompaction {
namespace Thrust {

/**
 * Performs prefix-sum (aka scan) on idata, storing the result into odata.
 */
void scan(int n, int *odata, const int *idata) {
    // TODO use `thrust::exclusive_scan`
    // example: for device_vectors dv_in and dv_out:
    // thrust::exclusive_scan(dv_in.begin(), dv_in.end(), dv_out.begin());

    thrust::device_vector<int> dev_idata(idata, idata + n);
    thrust::device_vector<int> dev_odata(odata, odata + n);
	auto start = std::chrono::system_clock::now();
	//thrust::exclusive_scan(idata, idata + n, odata);
	thrust::exclusive_scan(dev_idata.begin(), dev_idata.end(), dev_odata.begin());
	auto end   = std::chrono::system_clock::now();
	thrust::copy(dev_odata.begin(), dev_odata.end(), odata);
	
	//auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
	auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count();
	//std::cout << duration << std::endl;
	FILE* fp = fopen("efficient.txt", "a+");
	fprintf(fp, "%d %I64d\n", ilog2ceil(n), duration);
	fclose(fp);
}

}
}
