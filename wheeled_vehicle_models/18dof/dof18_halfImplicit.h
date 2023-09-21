#ifndef DOF18_HALFIMPLICIT_H
#define DOF18_HALFIMPLICIT_H

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <vector>

#include "dof18.h"

// =============================================================================
// Define the solver class
// =============================================================================

class d18SolverHalfImplicit {
  public:
    d18SolverHalfImplicit();
    ~d18SolverHalfImplicit();

    // Construct the solver with the specified vehicle
    // and tire parameters and the driver inputs.
    void Construct(const std::string& veh_params_file,
                   const std::string& tire_params_file,
                   const std::string& driver_file);
    // Set the solver time step
    void SetTimeStep(double step) { m_step = step; }

    // Set the output file path
    void SetOutput(const std::string& output_file, double output_freq);

    // Solve uptill the end time specified in the driver inputs
    void Solve();

    // Initialize function in case user wants non-zero intializations
    void Initialize(d18::VehicleState& vehicle_states,
                    d18::TMeasyState& tire_states_LF,
                    d18::TMeasyState& tire_states_RF,
                    d18::TMeasyState& tire_states_LR,
                    d18::TMeasyState& tire_states_RR);

    void IntegrateStep(double t, double throttle, double steering, double braking);

    void WriteToFile();

    // Vehicle states and tire states
    d18::VehicleState m_veh_state;
    d18::TMeasyState m_tirelf_state;
    d18::TMeasyState m_tirerf_state;
    d18::TMeasyState m_tirelr_state;
    d18::TMeasyState m_tirerr_state;

    CSV_writer m_csv;

  private:
    void Integrate();

    void Write(double t);

    void rhsFun(double t);

    void rhsFun(double t, DriverInput& controls);  // We need to provide controls when we are stepping

    double m_tend;                  // final integration time
    double m_step;                  // integration time step
    int m_timeStepsStored;          // Keeps track of time steps stored if we need data output
    bool m_output;                  // data output flag
    double m_dtout;                 // time interval between data output
    std::string m_output_file;      // output file path
    d18::VehicleParam m_veh_param;  // vehicle parameters
    d18::TMeasyParam m_tire_param;  // Tire parameters
    DriverData m_driver_data;       // driver inputs
};

#endif