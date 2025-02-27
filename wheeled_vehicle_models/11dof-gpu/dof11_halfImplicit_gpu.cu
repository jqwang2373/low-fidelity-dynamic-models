#include <algorithm>
#include <cassert>
#include <random>
#include <cmath>
#include <iostream>
#include <stdint.h>
#include <vector>

#include "dof11_gpu.cuh"
#include "dof11_halfImplicit_gpu.cuh"

using namespace d11GPU;
// ======================================================================================================================
__host__ d11SolverHalfImplicitGPU::d11SolverHalfImplicitGPU(unsigned int total_num_vehicles)
    : m_step(0.001),
      m_output(false),
      m_vehicle_count_tracker_params(0),
      m_vehicle_count_tracker_states(0),
      m_kernel_sim_time(2.),
      m_host_dump_time(10.),
      m_threads_per_block(32),
      m_tend(0.) {
    m_total_num_vehicles = total_num_vehicles;

    // Allocate memory for the simData and simStates
    CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_data, sizeof(d11GPU::SimData) * m_total_num_vehicles));
    CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_data_nr, sizeof(d11GPU::SimDataNr) * m_total_num_vehicles));
    CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_states, sizeof(d11GPU::SimState) * m_total_num_vehicles));
    CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_states_nr, sizeof(d11GPU::SimStateNr) * m_total_num_vehicles));

    // Set device and host arrays to nullptrs in case SetOutput is not called by the user
    m_device_response = nullptr;
    m_host_response = nullptr;

    int deviceId = 0;         // Assume we are using GPU 0
    cudaSetDevice(deviceId);  // Set the device
}
__host__ d11SolverHalfImplicitGPU::~d11SolverHalfImplicitGPU() {
    // Only need to delete the memory of the simData and simStates of the respective tire as the rest of the memory is
    // freed as soon as we have information of what tire the user is using
    if (m_tire_type == TireType::TMeasy) {
        cudaFree(m_sim_data);
        cudaFree(m_sim_states);
    } else {
        cudaFree(m_sim_data_nr);
        cudaFree(m_sim_states_nr);
    }
    cudaFree(m_device_response);
    delete[] m_host_response;
}
// ======================================================================================================================
// Construct the solver using path to vehicle parameters, tire parameters, number of vehicles and driver
__host__ void d11SolverHalfImplicitGPU::Construct(const std::string& vehicle_params_file,
                                                  const std::string& tire_params_file,
                                                  unsigned int num_vehicles,
                                                  const std::string& driver_inputs_file) {
    // Check if num_vehicles added is less than the total number of vehicles
    assert((num_vehicles + m_vehicle_count_tracker_params <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    // If there is no tire type specified, then use TMeasy
    m_tire_type = TireType::TMeasy;
    // Because of this, we free the memory of the TMeasyNR tire
    cudaFree(m_sim_data_nr);
    cudaFree(m_sim_states_nr);
    // Set these to nullptr so that we don't try to free them again in the destructor
    m_sim_data_nr = nullptr;
    m_sim_states_nr = nullptr;

    // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them up
    // and then copy them over to the simData structs
    d11GPU::VehicleParam veh_param;
    d11GPU::TMeasyParam tire_param;

    setVehParamsJSON(veh_param, vehicle_params_file.c_str());
    setTireParamsJSON(tire_param, tire_params_file.c_str());
    // Initialize tire parameters that depend on other parameters
    tireInit(&tire_param);

    DriverData driver_data;
    LoadDriverData(driver_data, driver_inputs_file);
    unsigned int driver_data_len = driver_data.size();
    size_t old_vehicle_count = m_vehicle_count_tracker_params;
    m_vehicle_count_tracker_params += num_vehicles;
    for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
        m_sim_data[i]._driver_data_len = driver_data_len;
        // Allocate memory for the driver data
        CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_data[i]._driver_data,
                                           sizeof(DriverInput) * m_sim_data[i]._driver_data_len));
        // Copy the driver data from cpu to managed memory
        std::copy(driver_data.begin(), driver_data.end(), m_sim_data[i]._driver_data);
        // Fill up simulation data from the cpu structs
        m_sim_data[i]._veh_param = veh_param;
        m_sim_data[i]._tireTM_param = tire_param;
    }
    CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data, sizeof(m_sim_data[0]) * m_vehicle_count_tracker_params,
                                          0));  // move the simData onto the GPU
}

__host__ void d11SolverHalfImplicitGPU::Construct(const std::string& vehicle_params_file,
                                                  const std::string& tire_params_file,
                                                  unsigned int num_vehicles,
                                                  const std::string& driver_inputs_file,
                                                  TireType type) {
    // Check if num_vehicles added is less than the total number of vehicles
    assert((num_vehicles + m_vehicle_count_tracker_params <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    // If there is no tire type specified, then use TMeasy
    m_tire_type = type;

    if (m_tire_type == TireType::TMeasy) {
        // Because of this, we free the memory of the TMeasyNR tire
        cudaFree(m_sim_data_nr);
        cudaFree(m_sim_states_nr);
        // Set these to nullptr so that we don't try to free them again in the destructor
        m_sim_data_nr = nullptr;
        m_sim_states_nr = nullptr;

        // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them
        // up and then copy them over to the simData structs
        d11GPU::VehicleParam veh_param;
        d11GPU::TMeasyParam tire_param;

        setVehParamsJSON(veh_param, vehicle_params_file.c_str());
        setTireParamsJSON(tire_param, tire_params_file.c_str());
        // Initialize tire parameters that depend on other parameters
        tireInit(&tire_param);

        DriverData driver_data;
        LoadDriverData(driver_data, driver_inputs_file);
        unsigned int driver_data_len = driver_data.size();
        size_t old_vehicle_count = m_vehicle_count_tracker_params;
        m_vehicle_count_tracker_params += num_vehicles;
        for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
            m_sim_data[i]._driver_data_len = driver_data_len;
            // Allocate memory for the driver data
            CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_data[i]._driver_data,
                                               sizeof(DriverInput) * m_sim_data[i]._driver_data_len));
            // Copy the driver data from cpu to managed memory
            std::copy(driver_data.begin(), driver_data.end(), m_sim_data[i]._driver_data);
            // Fill up simulation data from the cpu structs
            m_sim_data[i]._veh_param = veh_param;
            m_sim_data[i]._tireTM_param = tire_param;
        }
        CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data, sizeof(m_sim_data[0]) * m_vehicle_count_tracker_params,
                                              0));  // move the simData onto the GPU
    } else {
        // Because of this, we free the memory of the TMeasyNR tire
        cudaFree(m_sim_data);
        cudaFree(m_sim_states);
        // Set these to nullptr so that we don't try to free them again in the destructor
        m_sim_data = nullptr;
        m_sim_states = nullptr;

        // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them
        // up and then copy them over to the simData structs
        d11GPU::VehicleParam veh_param;
        d11GPU::TMeasyNrParam tire_param;

        setVehParamsJSON(veh_param, vehicle_params_file.c_str());
        setTireParamsJSON(tire_param, tire_params_file.c_str());
        // Initialize tire parameters that depend on other parameters
        tireInit(&tire_param);

        DriverData driver_data;
        LoadDriverData(driver_data, driver_inputs_file);
        unsigned int driver_data_len = driver_data.size();
        size_t old_vehicle_count = m_vehicle_count_tracker_params;
        m_vehicle_count_tracker_params += num_vehicles;
        for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
            m_sim_data_nr[i]._driver_data_len = driver_data_len;
            // Allocate memory for the driver data
            CHECK_CUDA_ERROR(cudaMallocManaged((void**)&m_sim_data_nr[i]._driver_data,
                                               sizeof(DriverInput) * m_sim_data_nr[i]._driver_data_len));
            // Copy the driver data from cpu to managed memory
            std::copy(driver_data.begin(), driver_data.end(), m_sim_data_nr[i]._driver_data);
            // Fill up simulation data from the cpu structs
            m_sim_data_nr[i]._veh_param = veh_param;
            m_sim_data_nr[i]._tireTMNr_param = tire_param;
        }
        CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data_nr, sizeof(m_sim_data_nr[0]) * m_vehicle_count_tracker_params,
                                              0));  // move the simData onto the GPU
    }
}

// Overload for situations when a controller is used and we don't have a driver data file
__host__ void d11SolverHalfImplicitGPU::Construct(const std::string& vehicle_params_file,
                                                  const std::string& tire_params_file,
                                                  unsigned int num_vehicles) {
    // Check if num_vehicles added is less than the total number of vehicles
    assert((num_vehicles + m_vehicle_count_tracker_params <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    // If there is no tire type specified, then use TMeasy
    m_tire_type = TireType::TMeasy;
    // Because of this, we free the memory of the TMeasyNR tire
    cudaFree(m_sim_data_nr);
    cudaFree(m_sim_states_nr);
    // Set these to nullptr so that we don't try to free them again in the destructor
    m_sim_data_nr = nullptr;
    m_sim_states_nr = nullptr;

    // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them up
    // and then copy them over to the simData structs
    d11GPU::VehicleParam veh_param;
    d11GPU::TMeasyParam tire_param;

    setVehParamsJSON(veh_param, vehicle_params_file.c_str());
    setTireParamsJSON(tire_param, tire_params_file.c_str());
    // Initialize tire parameters that depend on other parameters
    tireInit(&tire_param);

    size_t old_vehicle_count = m_vehicle_count_tracker_params;
    m_vehicle_count_tracker_params += num_vehicles;
    for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
        // Fill up simulation data from the cpu structs
        m_sim_data[i]._veh_param = veh_param;
        m_sim_data[i]._tireTM_param = tire_param;
    }

    CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data, sizeof(m_sim_data[0]) * m_vehicle_count_tracker_params,
                                          0));  // move the simData onto the GPU
}
__host__ void d11SolverHalfImplicitGPU::Construct(const std::string& vehicle_params_file,
                                                  const std::string& tire_params_file,
                                                  unsigned int num_vehicles,
                                                  TireType type) {
    // Check if num_vehicles added is less than the total number of vehicles
    assert((num_vehicles + m_vehicle_count_tracker_params <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    m_tire_type = type;
    // If there is no tire type specified, then use TMeasy
    if (m_tire_type == TireType::TMeasy) {
        // Because of this, we free the memory of the TMeasyNR tire
        cudaFree(m_sim_data_nr);
        cudaFree(m_sim_states_nr);
        // Set these to nullptr so that we don't try to free them again in the destructor
        m_sim_data_nr = nullptr;
        m_sim_states_nr = nullptr;

        // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them
        // up and then copy them over to the simData structs
        d11GPU::VehicleParam veh_param;
        d11GPU::TMeasyParam tire_param;

        setVehParamsJSON(veh_param, vehicle_params_file.c_str());
        setTireParamsJSON(tire_param, tire_params_file.c_str());
        // Initialize tire parameters that depend on other parameters
        tireInit(&tire_param);

        size_t old_vehicle_count = m_vehicle_count_tracker_params;
        m_vehicle_count_tracker_params += num_vehicles;
        for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
            // Fill up simulation data from the cpu structs
            m_sim_data[i]._veh_param = veh_param;
            m_sim_data[i]._tireTM_param = tire_param;
        }
        CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data, sizeof(m_sim_data[0]) * m_vehicle_count_tracker_params,
                                              0));  // move the simData onto the GPU
    } else {
        // Because of this, we free the memory of the TMeasyNR tire
        cudaFree(m_sim_data);
        cudaFree(m_sim_states);
        // Set these to nullptr so that we don't try to free them again in the destructor
        m_sim_data = nullptr;
        m_sim_states = nullptr;

        // Since cudaMallocManaged does not call the constructor for non-POD types, we create cpu structs and fill them
        // up and then copy them over to the simData structs
        d11GPU::VehicleParam veh_param;
        d11GPU::TMeasyNrParam tire_param;

        setVehParamsJSON(veh_param, vehicle_params_file.c_str());
        setTireParamsJSON(tire_param, tire_params_file.c_str());
        // Initialize tire parameters that depend on other parameters
        tireInit(&tire_param);

        size_t old_vehicle_count = m_vehicle_count_tracker_params;
        m_vehicle_count_tracker_params += num_vehicles;
        for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_params; i++) {
            // Fill up simulation data from the cpu structs
            m_sim_data_nr[i]._veh_param = veh_param;
            m_sim_data_nr[i]._tireTMNr_param = tire_param;
        }
        CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_data_nr, sizeof(m_sim_data_nr[0]) * m_vehicle_count_tracker_params,
                                              0));  // move the simData onto the GPU
    }
}

// ======================================================================================================================

void d11SolverHalfImplicitGPU::Initialize(d11GPU::VehicleState& vehicle_states,
                                          d11GPU::TMeasyState& tire_states_F,
                                          d11GPU::TMeasyState& tire_states_R,
                                          unsigned int num_vehicles) {
    // Esnure that construct was called with TMeasy tire type
    assert((m_tire_type == TireType::TMeasy) &&
           "Construct function called with TMeasyNr tire type, but Initialize called with TMeasy tire type");
    assert((num_vehicles + m_vehicle_count_tracker_states <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    size_t old_vehicle_count = m_vehicle_count_tracker_states;
    m_vehicle_count_tracker_states += num_vehicles;
    for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_states; i++) {
        // Fill up simulation data from the cpu structs
        m_sim_states[i]._veh_state = vehicle_states;
        m_sim_states[i]._tiref_state = tire_states_F;
        m_sim_states[i]._tirer_state = tire_states_R;
    }
    CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_states, sizeof(SimState) * m_vehicle_count_tracker_states,
                                          0));  // move the simState onto the GPU
}

void d11SolverHalfImplicitGPU::Initialize(d11GPU::VehicleState& vehicle_states,
                                          d11GPU::TMeasyNrState& tire_states_F,
                                          d11GPU::TMeasyNrState& tire_states_R,
                                          unsigned int num_vehicles) {
    // Esnure that construct was called with TMeasyNr tire type
    assert((m_tire_type == TireType::TMeasyNr) &&
           "Construct function called with TMeasy tire type, but Initialize called with TMeasyNR tire type");
    assert((num_vehicles + m_vehicle_count_tracker_states <= m_total_num_vehicles) &&
           "Number of vehicles added makes the vehicle count greater than the total number of vehicles");
    size_t old_vehicle_count = m_vehicle_count_tracker_states;
    m_vehicle_count_tracker_states += num_vehicles;
    for (size_t i = old_vehicle_count; i < m_vehicle_count_tracker_states; i++) {
        // Fill up simulation data from the cpu structs
        m_sim_states_nr[i]._veh_state = vehicle_states;
        m_sim_states_nr[i]._tiref_state = tire_states_F;
        m_sim_states_nr[i]._tirer_state = tire_states_R;
    }
    CHECK_CUDA_ERROR(cudaMemPrefetchAsync(m_sim_states_nr, sizeof(SimState) * m_vehicle_count_tracker_states,
                                          0));  // move the simState onto the GPU
}
// ======================================================================================================================

__host__ void d11SolverHalfImplicitGPU::SetOutput(const std::string& output_file,
                                                  double output_freq,
                                                  bool store_all,
                                                  unsigned int no_outs) {
    m_output = true;
    m_store_all = store_all;
    if (!m_store_all) {
        // Check if number of outputs asked is greater than the total number of vehicles, if this is the case, raise
        // awarning and set to m_total_num_vehicles
        if (no_outs > m_total_num_vehicles) {
            std::cout << "Number of outputs asked is greater than the total number of vehicles, setting number of "
                         "outputs to total number of vehicles"
                      << std::endl;
            no_outs = m_total_num_vehicles;
        }
        m_num_outs = no_outs;
        // If store_all is false, randomly assign which vehicles need to be dumped into csv
        float some_seed = 68;
        std::mt19937 generator(some_seed);

        // Generate a range of numbers and shuffle them
        std::vector<int> numbers(m_total_num_vehicles);
        std::iota(numbers.begin(), numbers.end(), 0);  // Fill with values from 0 to m_total_num_vehicles - 1
        std::shuffle(numbers.begin(), numbers.end(), generator);

        // Resize m_which_outs and assign the first 'no_outs' numbers from the shuffled range
        m_which_outs.resize(no_outs);
        std::copy(numbers.begin(), numbers.begin() + no_outs, m_which_outs.begin());
    } else {
        m_num_outs = m_total_num_vehicles;
    }
    // Allocate memory for the csv_writers
    m_csv_writers_ptr = std::make_unique<CSV_writer[]>(m_num_outs);
    m_output_file = output_file;
    m_dtout = 1.0 / output_freq;

    // Here we also initialize the device and host arrays that store the response across vehicles and states -> If
    // output is not required, then nothing is stored, however the user has access to the states at the last time step
    // through the simState and simData structs

    // Number of time steps to be collected on the device
    m_device_collection_timeSteps = ceil(m_kernel_sim_time / m_dtout);

    // Number of states to store -> For now we only allow storage of the major states which are common to both tire
    // models [time,x,y,u,v,psi,wz,f_omega,r_omega]
    m_collection_states = 9;

    // Thus device array size becomes
    m_device_size = sizeof(double) * m_total_num_vehicles * m_collection_states * (m_device_collection_timeSteps);

    CHECK_CUDA_ERROR(cudaMalloc((void**)&m_device_response, m_device_size));

    // Now the host response
    m_host_collection_timeSteps = ceil(m_host_dump_time / m_dtout);

    // Thus the host size becomes -> Usually much larger than the device size
    m_host_response = new double[m_total_num_vehicles * m_collection_states * (m_host_collection_timeSteps)]();
}

// ======================================================================================================================

/// @brief Solve the system of equations by calling the integrate function
__host__ void d11SolverHalfImplicitGPU::Solve() {
    assert(m_tend != 0. && "Final time not set, please use SetEndTime function");
    // Calculate the number of blocks required
    m_num_blocks = (m_total_num_vehicles + m_threads_per_block - 1) / m_threads_per_block;
#ifdef DEBUG
    std::cout << "Number of blocks: " << m_num_blocks << std::endl;
    std::cout << "Number of threads per block: " << m_threads_per_block << std::endl;
    std::cout << "Total number of vehicles: " << m_total_num_vehicles << std::endl;
#endif
    // If m_output is false, then we still need to initialize device array -> We don't need the host array as its
    // purpose is just to store the final output
    if (!m_output) {
        // Number of time steps to be collected on the device
        m_device_collection_timeSteps = ceil(m_kernel_sim_time / m_dtout);

        // Number of states to store -> For now we only allow storage of the major states which are common to both tire
        // models [time,x,y,u,v,psi,wz,f_omega,r_omega]
        m_collection_states = 9;

        // Thus device array size becomes
        m_device_size = sizeof(double) * m_total_num_vehicles * m_collection_states * (m_device_collection_timeSteps);

        CHECK_CUDA_ERROR(cudaMalloc((void**)&m_device_response, m_device_size));
    }

    double current_time = 0.;
    unsigned int kernel_launches_since_last_dump = 0;  // Track the number of kernel launches since the last dump of the
                                                       // host response
    double time_since_last_dump = 0.;                  // Track the time since the last dump of the host response
    // Write the initial conditions
    if (m_output) {
        Write(current_time);
    }

    while (current_time < m_tend) {
        // Calculate when this kernel is supposed to end

        double kernel_end_time = current_time + m_kernel_sim_time;

        // Launch the kernel
        if (m_tire_type == TireType::TMeasy) {
            Integrate<<<m_num_blocks, m_threads_per_block>>>(current_time, m_kernel_sim_time, m_step, m_output,
                                                             m_total_num_vehicles, m_collection_states, m_dtout,
                                                             m_device_response, m_sim_data, m_sim_states);
            cudaError_t err = cudaGetLastError();
            if (err != cudaSuccess) {
                fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(err));
            }
        } else {
            Integrate<<<m_num_blocks, m_threads_per_block>>>(current_time, m_kernel_sim_time, m_step, m_output,
                                                             m_total_num_vehicles, m_collection_states, m_dtout,
                                                             m_device_response, m_sim_data_nr, m_sim_states_nr);
            cudaError_t err = cudaGetLastError();
            if (err != cudaSuccess) {
                fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(err));
            }
        }

        // Get the new time the simulation has reached
        current_time = kernel_end_time;
        time_since_last_dump += m_kernel_sim_time;

        // If we have to save output, copy over the device into the response
        if (m_output) {
            // Amount of respoonse already filled
            unsigned int filled_response = m_total_num_vehicles * m_collection_states * m_device_collection_timeSteps *
                                           kernel_launches_since_last_dump;

            // Copy the device to the right part of the host response
            CHECK_CUDA_ERROR(cudaMemcpy(m_host_response + filled_response, m_device_response, m_device_size,
                                        cudaMemcpyDeviceToHost));

            kernel_launches_since_last_dump++;
            // Check if host is full and dump that into a csv writer
            if (abs(time_since_last_dump - m_host_dump_time) < 1e-6) {
                Write(current_time);
                time_since_last_dump = 0.;
                kernel_launches_since_last_dump = 0;
            }
        }
    }
    // If the simulation ended at a non multiple of m_host_dump_time, we dump the remaining data
    if (m_output && (kernel_launches_since_last_dump != 0)) {
        unsigned int time_steps_to_write = kernel_launches_since_last_dump * m_device_collection_timeSteps;
        Write(current_time, time_steps_to_write);
    }
    // End of simulation, write to the csv file
    if (m_output) {
        WriteToFile();
    }
}

//======================================================================================================================
__host__ double d11SolverHalfImplicitGPU::SolveStep(double t,
                                                    double steering,
                                                    double throttle,
                                                    double braking) {  // Calculate the number of blocks required
    // if m_output is true, then raise assertion
    if (m_output) {
        // Handle the error: log, return an error code, etc.
        std::cerr << "Cannot get csv file output if SolveStep is called, please access sim_states through GetSimSate"
                  << std::endl;
        exit(EXIT_FAILURE);
    }
    m_num_blocks = (m_total_num_vehicles + m_threads_per_block - 1) / m_threads_per_block;
    // If m_output is false and its the first time step then we still need to initialize device array -> We don't need
    // the host array as its purpose is just to store the final output
    if (t == 0.) {
        // Number of time steps to be collected on the device
        m_device_collection_timeSteps = ceil(m_kernel_sim_time / m_dtout);

        // Number of states to store -> For now we only allow storage of the major states which are common to both tire
        // models [time,x,y,u,v,psi,wz,f_omega,r_omega]
        m_collection_states = 9;

        // Thus device array size becomes
        m_device_size = sizeof(double) * m_total_num_vehicles * m_collection_states * (m_device_collection_timeSteps);

        CHECK_CUDA_ERROR(cudaMalloc((void**)&m_device_response, m_device_size));
    }
    m_current_time = t;

    // Launch the kernel
    double kernel_end_time = m_current_time + m_kernel_sim_time;

    if (m_tire_type == TireType::TMeasy) {
        Integrate<<<m_num_blocks, m_threads_per_block>>>(m_current_time, steering, throttle, braking, m_kernel_sim_time,
                                                         m_step, m_output, m_total_num_vehicles, m_collection_states,
                                                         m_dtout, m_device_response, m_sim_data, m_sim_states);
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(err));
        }
    } else {
        Integrate<<<m_num_blocks, m_threads_per_block>>>(m_current_time, steering, throttle, braking, m_kernel_sim_time,
                                                         m_step, m_output, m_total_num_vehicles, m_collection_states,
                                                         m_dtout, m_device_response, m_sim_data_nr, m_sim_states_nr);
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "Kernel launch failed: %s\n", cudaGetErrorString(err));
        }
    }

    m_current_time = kernel_end_time;
    m_time_since_last_dump += m_kernel_sim_time;
    return m_current_time;
}
//======================================================================================================================

//======================================================================================================================
__host__ void d11SolverHalfImplicitGPU::Write(double t, unsigned int time_steps_to_write) {
    unsigned int loop_limit = 0;
    if (m_store_all) {
        loop_limit = m_total_num_vehicles;
    } else {
        loop_limit = m_num_outs;
    }

    // If time_steps_to_write is not specified, we write all the data
    if (time_steps_to_write == 0) {
        time_steps_to_write = m_host_collection_timeSteps;
    }

    if (t < m_step) {
        for (unsigned int sim_no = 0; sim_no < loop_limit; sim_no++) {
            CSV_writer& csv = m_csv_writers_ptr[sim_no];
            csv << "time";
            csv << "x";
            csv << "y";
            csv << "vx";
            csv << "vy";
            csv << "yaw";
            csv << "yaw_rate";
            csv << "wf";
            csv << "wr";
            csv << std::endl;

            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << 0;
            csv << std::endl;
        }
        return;
    } else {
        for (unsigned int sim_no = 0; sim_no < loop_limit; sim_no++) {
            unsigned int index_by = 0;
            // If we are no storing all, we will have to index by random numbers
            if (m_store_all) {
                index_by = sim_no;
            } else {
                index_by = m_which_outs[sim_no];
            }
            CSV_writer& csv = m_csv_writers_ptr[sim_no];
            unsigned int steps_written = 0;
            while (steps_written < time_steps_to_write) {
                unsigned int time_offset = steps_written * m_total_num_vehicles * m_collection_states;
                csv << m_host_response[time_offset + (m_total_num_vehicles * 0) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 1) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 2) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 3) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 4) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 5) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 6) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 7) + index_by];
                csv << m_host_response[time_offset + (m_total_num_vehicles * 8) + index_by];
                csv << std::endl;
                steps_written++;
            }
        }
    }
}

// ======================================================================================================================

__host__ void d11SolverHalfImplicitGPU::WriteToFile() {
    if (!m_output) {
        std::cout << "No output file specified. Call SetOutput() before calling WriteToFile()" << std::endl;
        return;
    }
    unsigned int loop_limit = 0;
    if (m_store_all) {
        loop_limit = m_total_num_vehicles;
    } else {
        loop_limit = m_num_outs;
    }
    for (unsigned int sim_no = 0; sim_no < loop_limit; sim_no++) {
        unsigned int index_by = 0;
        // If we are no storing all, we will have to index by random numbers
        if (m_store_all) {
            index_by = sim_no;
        } else {
            index_by = m_which_outs[sim_no];
        }
        if (m_tire_type == TireType::TMeasy) {
            CSV_writer& csv = m_csv_writers_ptr[sim_no];
            csv.write_to_file(m_output_file + "_" + std::to_string(index_by) + ".csv");
            csv.clearData();
        } else {
            CSV_writer& csv = m_csv_writers_ptr[sim_no];
            csv.write_to_file(m_output_file + "_" + std::to_string(index_by) + ".csv");
            csv.clearData();
        }
    }
}
// ======================================================================================================================
__host__ SimState d11SolverHalfImplicitGPU::GetSimState(unsigned int vehicle_index) {
    assert((vehicle_index < m_total_num_vehicles) && "Vehicle index out of bounds");

    // Allocate space for a single SimState on the host
    SimState host_state;

    if (m_tire_type == TireType::TMeasy) {
        // Copy the specific SimState from the GPU to the host
        cudaMemcpy(&host_state, &m_sim_states[vehicle_index], sizeof(SimState), cudaMemcpyDeviceToHost);
    } else {
        // Similarly for m_sim_states_nr
        cudaMemcpy(&host_state, &m_sim_states_nr[vehicle_index], sizeof(SimState), cudaMemcpyDeviceToHost);
    }

    return host_state;
}
// ======================================================================================================================
__device__ void rhsFun(double t, unsigned int total_num_vehicles, SimData* sim_data, SimState* sim_states) {
    // Get the vehicle index
    unsigned int vehicle_index = blockIdx.x * blockDim.x + threadIdx.x;

    if (vehicle_index < total_num_vehicles) {
        // All vehicles have one or the other tire type and thus no thread divergence
        VehicleParam& veh_param = sim_data[vehicle_index]._veh_param;
        VehicleState& veh_state = sim_states[vehicle_index]._veh_state;
        TMeasyParam& tireTM_param = sim_data[vehicle_index]._tireTM_param;
        TMeasyState& tireTMf_state = sim_states[vehicle_index]._tiref_state;
        TMeasyState& tireTMr_state = sim_states[vehicle_index]._tirer_state;

        DriverInput* driver_data = sim_data[vehicle_index]._driver_data;
        unsigned int len = sim_data[vehicle_index]._driver_data_len;
        // Get controls at the current timeStep
        auto controls = GetDriverInput(t, driver_data, len);

        double loads[2] = {0., 0.};
        // Compute the tire loads
        computeTireLoads(&loads[0], &veh_state, &veh_param, &tireTM_param);
        // Transform from vehicle frame to the tire frame
        vehToTireTransform(&tireTMf_state, &tireTMr_state, &veh_state, &loads[0], &veh_param, controls.m_steering);

        // Tire velocities using TMEasy tire
        computeTireRHS(&tireTMf_state, &tireTM_param, &veh_param, controls.m_steering);
        computeTireRHS(&tireTMr_state, &tireTM_param, &veh_param, 0);

        // Powertrain dynamics
        computePowertrainRHS(&veh_state, &tireTMf_state, &tireTMr_state, &veh_param, &tireTM_param, &controls);
        // Vehicle dynamics
        tireToVehTransform(&tireTMf_state, &tireTMr_state, &veh_state, &veh_param, controls.m_steering);

        double fx[2] = {tireTMf_state._fx, tireTMr_state._fx};
        double fy[2] = {tireTMf_state._fy, tireTMr_state._fy};

        computeVehRHS(&veh_state, &veh_param, &fx[0], &fy[0]);
    }
}
//======================================================================================================================
__device__ void rhsFun(double t,
                       unsigned int total_num_vehicles,
                       d11GPU::SimData* sim_data,
                       d11GPU::SimState* sim_states,
                       double steering,
                       double throttle,
                       double braking) {
    // Get the vehicle index
    unsigned int vehicle_index = blockIdx.x * blockDim.x + threadIdx.x;

    if (vehicle_index < total_num_vehicles) {
        // All vehicles have one or the other tire type and thus no thread divergence
        VehicleParam& veh_param = sim_data[vehicle_index]._veh_param;
        VehicleState& veh_state = sim_states[vehicle_index]._veh_state;
        TMeasyParam& tireTM_param = sim_data[vehicle_index]._tireTM_param;
        TMeasyState& tireTMf_state = sim_states[vehicle_index]._tiref_state;
        TMeasyState& tireTMr_state = sim_states[vehicle_index]._tirer_state;

        // Get controls at the current timeStep
        DriverInput controls;
        controls.m_steering = steering;
        controls.m_throttle = throttle;
        controls.m_braking = braking;

        double loads[2] = {0., 0.};
        // Compute the tire loads
        computeTireLoads(&loads[0], &veh_state, &veh_param, &tireTM_param);
        // Transform from vehicle frame to the tire frame
        vehToTireTransform(&tireTMf_state, &tireTMr_state, &veh_state, &loads[0], &veh_param, controls.m_steering);

        // Tire velocities using TMEasy tire
        computeTireRHS(&tireTMf_state, &tireTM_param, &veh_param, controls.m_steering);
        computeTireRHS(&tireTMr_state, &tireTM_param, &veh_param, 0.);

        // Powertrain dynamics
        computePowertrainRHS(&veh_state, &tireTMf_state, &tireTMr_state, &veh_param, &tireTM_param, &controls);
        // Vehicle dynamics
        tireToVehTransform(&tireTMf_state, &tireTMr_state, &veh_state, &veh_param, controls.m_steering);

        double fx[2] = {tireTMf_state._fx, tireTMr_state._fx};
        double fy[2] = {tireTMf_state._fy, tireTMr_state._fy};

        computeVehRHS(&veh_state, &veh_param, &fx[0], &fy[0]);
    }
}

//======================================================================================================================

__device__ void rhsFun(double t,
                       unsigned int total_num_vehicles,
                       d11GPU::SimDataNr* sim_data_nr,
                       d11GPU::SimStateNr* sim_states_nr) {  // Get the vehicle index
    unsigned int vehicle_index = blockIdx.x * blockDim.x + threadIdx.x;

    if (vehicle_index < total_num_vehicles) {
        VehicleParam& veh_param = sim_data_nr[vehicle_index]._veh_param;
        VehicleState& veh_state = sim_states_nr[vehicle_index]._veh_state;
        TMeasyNrParam& tireTMNr_param = sim_data_nr[vehicle_index]._tireTMNr_param;
        TMeasyNrState& tireTMNrf_state = sim_states_nr[vehicle_index]._tiref_state;
        TMeasyNrState& tireTMNrr_state = sim_states_nr[vehicle_index]._tirer_state;

        DriverInput* driver_data = sim_data_nr[vehicle_index]._driver_data;
        unsigned int len = sim_data_nr[vehicle_index]._driver_data_len;
        // Get controls at the current timeStep
        auto controls = GetDriverInput(t, driver_data, len);

        double loads[2] = {0., 0.};

        // Compute the tire loads
        computeTireLoads(&loads[0], &veh_state, &veh_param, &tireTMNr_param);
        // Transform from vehicle frame to the tire frame
        vehToTireTransform(&tireTMNrf_state, &tireTMNrr_state, &veh_state, &loads[0], &veh_param, controls.m_steering);
        // Tire velocities using TMEasyNr tire
        computeTireRHS(&tireTMNrf_state, &tireTMNr_param, &veh_param, controls.m_steering);
        computeTireRHS(&tireTMNrr_state, &tireTMNr_param, &veh_param, 0.);

        // Powertrain dynamics
        computePowertrainRHS(&veh_state, &tireTMNrf_state, &tireTMNrr_state, &veh_param, &tireTMNr_param, &controls);

        // Vehicle dynamics
        tireToVehTransform(&tireTMNrf_state, &tireTMNrr_state, &veh_state, &veh_param, controls.m_steering);

        double fx[2] = {tireTMNrf_state._fx, tireTMNrr_state._fx};
        double fy[2] = {tireTMNrf_state._fy, tireTMNrr_state._fy};

        computeVehRHS(&veh_state, &veh_param, &fx[0], &fy[0]);
    }
}

__device__ void rhsFun(double t,
                       unsigned int total_num_vehicles,
                       d11GPU::SimDataNr* sim_data_nr,
                       d11GPU::SimStateNr* sim_states_nr,
                       double steering,
                       double throttle,
                       double braking) {  // Get the vehicle index
    unsigned int vehicle_index = blockIdx.x * blockDim.x + threadIdx.x;

    if (vehicle_index < total_num_vehicles) {
        VehicleParam& veh_param = sim_data_nr[vehicle_index]._veh_param;
        VehicleState& veh_state = sim_states_nr[vehicle_index]._veh_state;
        TMeasyNrParam& tireTMNr_param = sim_data_nr[vehicle_index]._tireTMNr_param;
        TMeasyNrState& tireTMNrf_state = sim_states_nr[vehicle_index]._tiref_state;
        TMeasyNrState& tireTMNrr_state = sim_states_nr[vehicle_index]._tirer_state;

        // Get controls at the current timeStep
        DriverInput controls;
        controls.m_steering = steering;
        controls.m_throttle = throttle;
        controls.m_braking = braking;

        double loads[2] = {0., 0.};

        // Compute the tire loads
        computeTireLoads(&loads[0], &veh_state, &veh_param, &tireTMNr_param);
        // Transform from vehicle frame to the tire frame
        vehToTireTransform(&tireTMNrf_state, &tireTMNrr_state, &veh_state, &loads[0], &veh_param, controls.m_steering);
        // Tire velocities using TMEasyNr tire
        computeTireRHS(&tireTMNrf_state, &tireTMNr_param, &veh_param, controls.m_steering);
        computeTireRHS(&tireTMNrr_state, &tireTMNr_param, &veh_param, 0.);

        // Powertrain dynamics
        computePowertrainRHS(&veh_state, &tireTMNrf_state, &tireTMNrr_state, &veh_param, &tireTMNr_param, &controls);

        // Vehicle dynamics
        tireToVehTransform(&tireTMNrf_state, &tireTMNrr_state, &veh_state, &veh_param, controls.m_steering);

        double fx[2] = {tireTMNrf_state._fx, tireTMNrr_state._fx};
        double fy[2] = {tireTMNrf_state._fy, tireTMNrr_state._fy};

        computeVehRHS(&veh_state, &veh_param, &fx[0], &fy[0]);
    }
}

//======================================================================================================================
__global__ void Integrate(double current_time,
                          double kernel_sim_time,
                          double step,
                          bool output,
                          unsigned int total_num_vehicles,
                          unsigned int collection_states,
                          double dtout,
                          double* device_response,
                          d11GPU::SimData* sim_data,
                          d11GPU::SimState* sim_states) {
    double t = current_time;           // Set the current time
    double kernel_time = 0;            // Time since kernel was launched
    unsigned int timeStep_stored = 0;  // Number of time steps already stored in the device response
    double end_time = (t + kernel_sim_time) - step / 10.;
    unsigned int vehicle_id = blockIdx.x * blockDim.x + threadIdx.x;  // Get the vehicle id
    if (vehicle_id < total_num_vehicles) {
        while (t < end_time) {
            // Call the RHS to get accelerations for all the vehicles
            rhsFun(t, total_num_vehicles, sim_data, sim_states);

            // Integrate according to half implicit method for second order states
            // Integrate according to explicit method for first order states

            // Extract the states of the vehicle and the tires
            d11GPU::VehicleState& v_states = sim_states[vehicle_id]._veh_state;
            d11GPU::VehicleParam& veh_param = sim_data[vehicle_id]._veh_param;
            d11GPU::TMeasyState& tiref_st = sim_states[vehicle_id]._tiref_state;
            d11GPU::TMeasyState& tirer_st = sim_states[vehicle_id]._tirer_state;

            // First the tire states
            // F
            tiref_st._xe += tiref_st._xedot * step;
            tiref_st._ye += tiref_st._yedot * step;
            tiref_st._omega += tiref_st._dOmega * step;
            // R
            tirer_st._xe += tirer_st._xedot * step;
            tirer_st._ye += tirer_st._yedot * step;
            tirer_st._omega += tirer_st._dOmega * step;

            // Now the vehicle states
            if (veh_param._tcbool) {
                v_states._crankOmega += v_states._dOmega_crank * step;
            }

            // Integrate velocity level first
            v_states._u += v_states._udot * step;
            v_states._v += v_states._vdot * step;
            v_states._wz += v_states._wzdot * step;

            // Integrate position level next
            v_states._x += (v_states._u * cos(v_states._psi) - v_states._v * sin(v_states._psi)) * step;
            v_states._y += (v_states._u * sin(v_states._psi) + v_states._v * cos(v_states._psi)) * step;
            v_states._psi += v_states._wz * step;

            // Update time
            t += step;
            kernel_time += step;

            // Write to response if required -> regardless of no_outs or store_all we write all the vehicles to the
            // response
            if (output) {
                // The +1 here is because state at time 0 is not stored in device response
                if (abs(kernel_time - (timeStep_stored + 1) * dtout) < 1e-7) {
                    unsigned int time_offset = timeStep_stored * total_num_vehicles * collection_states;

                    device_response[time_offset + (total_num_vehicles * 0) + vehicle_id] = t;
                    device_response[time_offset + (total_num_vehicles * 1) + vehicle_id] = v_states._x;
                    device_response[time_offset + (total_num_vehicles * 2) + vehicle_id] = v_states._y;
                    device_response[time_offset + (total_num_vehicles * 3) + vehicle_id] = v_states._u;
                    device_response[time_offset + (total_num_vehicles * 4) + vehicle_id] = v_states._v;
                    device_response[time_offset + (total_num_vehicles * 5) + vehicle_id] = v_states._psi;
                    device_response[time_offset + (total_num_vehicles * 6) + vehicle_id] = v_states._wz;
                    device_response[time_offset + (total_num_vehicles * 7) + vehicle_id] = tiref_st._omega;
                    device_response[time_offset + (total_num_vehicles * 8) + vehicle_id] = tirer_st._omega;
                    timeStep_stored++;
                }
            }
        }
    }
}

__global__ void Integrate(double current_time,
                          double steering,
                          double throttle,
                          double braking,
                          double kernel_sim_time,
                          double step,
                          bool output,
                          unsigned int total_num_vehicles,
                          unsigned int collection_states,
                          double dtout,
                          double* device_response,
                          d11GPU::SimData* sim_data,
                          d11GPU::SimState* sim_states) {
    double t = current_time;           // Set the current time
    double kernel_time = 0;            // Time since kernel was launched
    unsigned int timeStep_stored = 0;  // Number of time steps already stored in the device response
    double end_time = (t + kernel_sim_time) - step / 10.;
    unsigned int vehicle_id = blockIdx.x * blockDim.x + threadIdx.x;  // Get the vehicle id
    if (vehicle_id < total_num_vehicles) {
        while (t < end_time) {
            // Call the RHS to get accelerations for all the vehicles
            rhsFun(t, total_num_vehicles, sim_data, sim_states, steering, throttle, braking);

            // Integrate according to half implicit method for second order states
            // Integrate according to explicit method for first order states

            // Extract the states of the vehicle and the tires
            d11GPU::VehicleState& v_states = sim_states[vehicle_id]._veh_state;
            d11GPU::VehicleParam& veh_param = sim_data[vehicle_id]._veh_param;
            d11GPU::TMeasyState& tiref_st = sim_states[vehicle_id]._tiref_state;
            d11GPU::TMeasyState& tirer_st = sim_states[vehicle_id]._tirer_state;

            // First the tire states
            // F
            tiref_st._xe += tiref_st._xedot * step;
            tiref_st._ye += tiref_st._yedot * step;
            tiref_st._omega += tiref_st._dOmega * step;
            // R
            tirer_st._xe += tirer_st._xedot * step;
            tirer_st._ye += tirer_st._yedot * step;
            tirer_st._omega += tirer_st._dOmega * step;

            // Now the vehicle states
            if (veh_param._tcbool) {
                v_states._crankOmega += v_states._dOmega_crank * step;
            }

            // Integrate velocity level first
            v_states._u += v_states._udot * step;
            v_states._v += v_states._vdot * step;
            v_states._wz += v_states._wzdot * step;

            // Integrate position level next
            v_states._x += (v_states._u * cos(v_states._psi) - v_states._v * sin(v_states._psi)) * step;
            v_states._y += (v_states._u * sin(v_states._psi) + v_states._v * cos(v_states._psi)) * step;
            v_states._psi += v_states._wz * step;

            // Update time
            t += step;
            kernel_time += step;

            // Write to response if required -> regardless of no_outs or store_all we write all the vehicles to the
            // response
            if (output) {
                // The +1 here is because state at time 0 is not stored in device response
                if (abs(kernel_time - (timeStep_stored + 1) * dtout) < 1e-7) {
                    unsigned int time_offset = timeStep_stored * total_num_vehicles * collection_states;

                    device_response[time_offset + (total_num_vehicles * 0) + vehicle_id] = t;
                    device_response[time_offset + (total_num_vehicles * 1) + vehicle_id] = v_states._x;
                    device_response[time_offset + (total_num_vehicles * 2) + vehicle_id] = v_states._y;
                    device_response[time_offset + (total_num_vehicles * 3) + vehicle_id] = v_states._u;
                    device_response[time_offset + (total_num_vehicles * 4) + vehicle_id] = v_states._v;
                    device_response[time_offset + (total_num_vehicles * 5) + vehicle_id] = v_states._psi;
                    device_response[time_offset + (total_num_vehicles * 6) + vehicle_id] = v_states._wz;
                    device_response[time_offset + (total_num_vehicles * 7) + vehicle_id] = tiref_st._omega;
                    device_response[time_offset + (total_num_vehicles * 8) + vehicle_id] = tirer_st._omega;
                    timeStep_stored++;
                }
            }
        }
    }
}

//======================================================================================================================
__global__ void Integrate(double current_time,
                          double kernel_sim_time,
                          double step,
                          bool output,
                          unsigned int total_num_vehicles,
                          unsigned int collection_states,
                          double dtout,
                          double* device_response,
                          d11GPU::SimDataNr* sim_data,
                          d11GPU::SimStateNr* sim_states) {
    double t = current_time;           // Set the current time
    double kernel_time = 0;            // Time since kernel was launched
    unsigned int timeStep_stored = 0;  // Number of time steps already stored in the device response
    double end_time = (t + kernel_sim_time) - step / 10.;
    unsigned int vehicle_id = blockIdx.x * blockDim.x + threadIdx.x;  // Get the vehicle id
    if (vehicle_id < total_num_vehicles) {
        while (t < end_time) {
            // Call the RHS to get accelerations for all the vehicles
            rhsFun(t, total_num_vehicles, sim_data, sim_states);

            // Integrate according to half implicit method for second order states
            // Integrate according to explicit method for first order states

            // Extract the states of the vehicle and the tires
            d11GPU::VehicleState& v_states = sim_states[vehicle_id]._veh_state;
            d11GPU::VehicleParam& veh_param = sim_data[vehicle_id]._veh_param;
            d11GPU::TMeasyNrState& tiref_st = sim_states[vehicle_id]._tiref_state;
            d11GPU::TMeasyNrState& tirer_st = sim_states[vehicle_id]._tirer_state;

            // First the tire states
            // F
            tiref_st._omega += tiref_st._dOmega * step;
            // R
            tirer_st._omega += tirer_st._dOmega * step;

            // Now the vehicle states
            if (veh_param._tcbool) {
                v_states._crankOmega += v_states._dOmega_crank * step;
            }

            // Integrate velocity level first
            v_states._u += v_states._udot * step;
            v_states._v += v_states._vdot * step;
            v_states._wz += v_states._wzdot * step;

            // Integrate position level next
            v_states._x += (v_states._u * cos(v_states._psi) - v_states._v * sin(v_states._psi)) * step;
            v_states._y += (v_states._u * sin(v_states._psi) + v_states._v * cos(v_states._psi)) * step;
            v_states._psi += v_states._wz * step;

            // Update time
            t += step;
            kernel_time += step;

            // Write to response if required -> regardless of no_outs or store_all we write all the vehicles to the
            // response
            if (output) {
                // The +1 here is because state at time 0 is not stored in device response
                if (abs(kernel_time - (timeStep_stored + 1) * dtout) < 1e-7) {
                    unsigned int time_offset = timeStep_stored * total_num_vehicles * collection_states;

                    device_response[time_offset + (total_num_vehicles * 0) + vehicle_id] = t;
                    device_response[time_offset + (total_num_vehicles * 1) + vehicle_id] = v_states._x;
                    device_response[time_offset + (total_num_vehicles * 2) + vehicle_id] = v_states._y;
                    device_response[time_offset + (total_num_vehicles * 3) + vehicle_id] = v_states._u;
                    device_response[time_offset + (total_num_vehicles * 4) + vehicle_id] = v_states._v;
                    device_response[time_offset + (total_num_vehicles * 5) + vehicle_id] = v_states._psi;
                    device_response[time_offset + (total_num_vehicles * 6) + vehicle_id] = v_states._wz;
                    device_response[time_offset + (total_num_vehicles * 7) + vehicle_id] = tiref_st._omega;
                    device_response[time_offset + (total_num_vehicles * 8) + vehicle_id] = tirer_st._omega;
                    timeStep_stored++;
                }
            }
        }
    }
}

__global__ void Integrate(double current_time,
                          double steering,
                          double throttle,
                          double braking,
                          double kernel_sim_time,
                          double step,
                          bool output,
                          unsigned int total_num_vehicles,
                          unsigned int collection_states,
                          double dtout,
                          double* device_response,
                          d11GPU::SimDataNr* sim_data,
                          d11GPU::SimStateNr* sim_states) {
    double t = current_time;           // Set the current time
    double kernel_time = 0;            // Time since kernel was launched
    unsigned int timeStep_stored = 0;  // Number of time steps already stored in the device response
    double end_time = (t + kernel_sim_time) - step / 10.;
    unsigned int vehicle_id = blockIdx.x * blockDim.x + threadIdx.x;  // Get the vehicle id
    if (vehicle_id < total_num_vehicles) {
        while (t < end_time) {
            // Call the RHS to get accelerations for all the vehicles
            rhsFun(t, total_num_vehicles, sim_data, sim_states, steering, throttle, braking);

            // Integrate according to half implicit method for second order states
            // Integrate according to explicit method for first order states

            // Extract the states of the vehicle and the tires
            d11GPU::VehicleState& v_states = sim_states[vehicle_id]._veh_state;
            d11GPU::VehicleParam& veh_param = sim_data[vehicle_id]._veh_param;
            d11GPU::TMeasyNrState& tiref_st = sim_states[vehicle_id]._tiref_state;
            d11GPU::TMeasyNrState& tirer_st = sim_states[vehicle_id]._tirer_state;

            // First the tire states
            // F
            tiref_st._omega += tiref_st._dOmega * step;
            // R
            tirer_st._omega += tirer_st._dOmega * step;

            // Now the vehicle states
            if (veh_param._tcbool) {
                v_states._crankOmega += v_states._dOmega_crank * step;
            }

            // Integrate velocity level first
            v_states._u += v_states._udot * step;
            v_states._v += v_states._vdot * step;
            v_states._wz += v_states._wzdot * step;

            // Integrate position level next
            v_states._x += (v_states._u * cos(v_states._psi) - v_states._v * sin(v_states._psi)) * step;
            v_states._y += (v_states._u * sin(v_states._psi) + v_states._v * cos(v_states._psi)) * step;
            v_states._psi += v_states._wz * step;

            // Update time
            t += step;
            kernel_time += step;

            // Write to response if required -> regardless of no_outs or store_all we write all the vehicles to the
            // response
            if (output) {
                // The +1 here is because state at time 0 is not stored in device response
                if (abs(kernel_time - (timeStep_stored + 1) * dtout) < 1e-7) {
                    unsigned int time_offset = timeStep_stored * total_num_vehicles * collection_states;

                    device_response[time_offset + (total_num_vehicles * 0) + vehicle_id] = t;
                    device_response[time_offset + (total_num_vehicles * 1) + vehicle_id] = v_states._x;
                    device_response[time_offset + (total_num_vehicles * 2) + vehicle_id] = v_states._y;
                    device_response[time_offset + (total_num_vehicles * 3) + vehicle_id] = v_states._u;
                    device_response[time_offset + (total_num_vehicles * 4) + vehicle_id] = v_states._v;
                    device_response[time_offset + (total_num_vehicles * 5) + vehicle_id] = v_states._psi;
                    device_response[time_offset + (total_num_vehicles * 6) + vehicle_id] = v_states._wz;
                    device_response[time_offset + (total_num_vehicles * 7) + vehicle_id] = tiref_st._omega;
                    device_response[time_offset + (total_num_vehicles * 8) + vehicle_id] = tirer_st._omega;
                    timeStep_stored++;
                }
            }
        }
    }
}