#ifndef DOF11_H
#define DOF11_H

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#include "utils.h"
// enum to decide what type of tire we have
enum class TireType { TMeasy, TMeasyNr };
namespace d11 {

// TMeasy parameter structure
struct TMeasyParam {
    // constructor that takes default values of HMMWV
    TMeasyParam()
        : _jw(6.69),
          _rr(0.015),
          _mu(0.8),
          _r0(0.4699),
          _pn(8562.8266),
          _pnmax(29969.893),
          _cx(185004.42),
          _cy(164448.37),
          _kt(411121.0),
          _dx(3700.),
          _dy(3488.),
          _rdyncoPn(0.375),
          _rdyncoP2n(0.75),
          _fzRdynco(0),
          _rdyncoCrit(0),
          _dfx0Pn(151447.29),
          _dfx0P2n(236412.79),
          _fxmPn(7575.3614),
          _fxmP2n(12808.276),
          _fxsPn(4657.9208),
          _fxsP2n(8625.3352),
          _sxmPn(0.12),
          _sxmP2n(0.15),
          _sxsPn(0.9),
          _sxsP2n(0.95),
          _dfy0Pn(50931.693),
          _dfy0P2n(94293.847),
          _fymPn(6615.0404),
          _fymP2n(12509.947),
          _fysPn(6091.5092),
          _fysP2n(11443.875),
          _symPn(0.38786),
          _symP2n(0.38786),
          _sysPn(0.82534),
          _sysP2n(0.91309),
          _step(1e-2) {}

    // constructor that takes given values - ugly looking code - can this be
    // beutified?
    TMeasyParam(double jw,
                double rr,
                double mu,
                double r0,
                double pn,
                double pnmax,
                double cx,
                double cy,
                double dx,
                double dy,
                double kt,
                double rdyncoPn,
                double rdyncoP2n,
                double fzRdynco,
                double rdyncoCrit,
                double dfx0Pn,
                double dfx0P2n,
                double fxmPn,
                double fxmP2n,
                double fxsPn,
                double fxsP2n,
                double sxmPn,
                double sxmP2n,
                double sxsPn,
                double sxsP2n,
                double dfy0Pn,
                double dfy0P2n,
                double fymPn,
                double fymP2n,
                double fysPn,
                double fysP2n,
                double symPn,
                double symP2n,
                double sysPn,
                double sysP2n,
                double step)
        : _jw(jw),
          _rr(rr),
          _mu(mu),
          _r0(r0),
          _pn(pn),
          _pnmax(pnmax),
          _cx(cx),
          _cy(cy),
          _kt(kt),
          _dx(dx),
          _dy(dy),
          _rdyncoPn(rdyncoPn),
          _rdyncoP2n(rdyncoP2n),
          _fzRdynco(fzRdynco),
          _rdyncoCrit(rdyncoCrit),
          _dfx0Pn(dfx0Pn),
          _dfx0P2n(dfx0P2n),
          _fxmPn(fxmPn),
          _fxmP2n(fxmP2n),
          _fxsPn(fxsPn),
          _fxsP2n(fxsP2n),
          _sxmPn(sxmPn),
          _sxmP2n(sxmP2n),
          _sxsPn(sxsPn),
          _sxsP2n(sxsP2n),
          _dfy0Pn(dfy0Pn),
          _dfy0P2n(dfy0P2n),
          _fymPn(fymPn),
          _fymP2n(fymP2n),
          _fysPn(fysPn),
          _fysP2n(fysP2n),
          _symPn(symPn),
          _symP2n(symP2n),
          _sysPn(sysPn),
          _sysP2n(sysP2n),
          _step(step) {}

    // copy constructor
    TMeasyParam(const TMeasyParam& other)
        : _jw(other._jw),
          _rr(other._rr),
          _mu(other._mu),
          _r0(other._r0),
          _pn(other._pn),
          _pnmax(other._pnmax),
          _cx(other._cx),
          _cy(other._cy),
          _kt(other._kt),
          _dx(other._dx),
          _dy(other._dy),
          _rdyncoPn(other._rdyncoPn),
          _rdyncoP2n(other._rdyncoP2n),
          _fzRdynco(other._fzRdynco),
          _rdyncoCrit(other._rdyncoCrit),
          _dfx0Pn(other._dfx0Pn),
          _dfx0P2n(other._dfx0P2n),
          _fxmPn(other._fxmPn),
          _fxmP2n(other._fxmP2n),
          _fxsPn(other._fxsPn),
          _fxsP2n(other._fxsP2n),
          _sxmPn(other._sxmPn),
          _sxmP2n(other._sxmP2n),
          _sxsPn(other._sxsPn),
          _sxsP2n(other._sxsP2n),
          _dfy0Pn(other._dfy0Pn),
          _dfy0P2n(other._dfy0P2n),
          _fymPn(other._fymPn),
          _fymP2n(other._fymP2n),
          _fysPn(other._fysPn),
          _fysP2n(other._fysP2n),
          _symPn(other._symPn),
          _symP2n(other._symP2n),
          _sysPn(other._sysPn),
          _sysP2n(other._sysP2n) {}

    // basic tire parameters
    double _jw;  // wheel inertia
    double _rr;  // rolling resistance of tire
    double _mu;  // friction constant
    double _r0;  // unloaded tire radius

    // TM easy specific tire params
    double _pn, _pnmax;    // nominal and max vertical force
    double _cx, _cy, _kt;  // longitudinal, lateral and vertical stiffness
    double _dx,
        _dy;  // longitudinal and lateral damping coeffs. No vertical damping

    // TM easy force characteristic params
    // 2 values - one at nominal load and one at max load

    // dynamic radius weighting coefficient and a critical value for the
    // vertical force
    double _rdyncoPn, _rdyncoP2n, _fzRdynco, _rdyncoCrit;

    // Longitudinal
    double _dfx0Pn, _dfx0P2n;  // intial longitudinal slopes dFx/dsx [N]
    double _fxmPn, _fxmP2n;    // maximum longituidnal force [N]
    double _fxsPn, _fxsP2n;    // Longitudinal load at sliding [N]
    double _sxmPn, _sxmP2n;    // slip sx at maximum longitudinal load Fx
    double _sxsPn, _sxsP2n;    // slip sx where sliding begins
    // Lateral
    double _dfy0Pn, _dfy0P2n;  // intial lateral slopes dFx/dsx [N]
    double _fymPn, _fymP2n;    // maximum lateral force [N]
    double _fysPn, _fysP2n;    // Lateral load at sliding [N]
    double _symPn, _symP2n;    // slip sx at maximum lateral load Fx
    double _sysPn, _sysP2n;    // slip sx where sliding begins

    double _step;  // integration time step
};

// Tm easy state structure - actual states + things that we need to keep track
// of
struct TMeasyState {
    // default contructor to 0's
    TMeasyState()
        : _xe(0.),
          _ye(0.),
          _xedot(0.),
          _yedot(0.),
          _omega(0.),
          _dOmega(0),
          _xt(0.),
          _rStat(0.),
          _fx(0.),
          _fy(0.),
          _fz(0.),
          _vsx(0.),
          _vsy(0.),
          _My(0.),
          _engTor(0.) {}

    // special constructor in case we want to start the simualtion at
    // some other time step
    TMeasyState(double xe,
                double ye,
                double xedot,
                double yedot,
                double omega,
                double xt,
                double rStat,
                double fx,
                double fy,
                double fz,
                double vsx,
                double vsy,
                double init_ratio)
        : _xe(xe),
          _ye(ye),
          _xedot(xedot),
          _yedot(yedot),
          _omega(omega),
          _xt(xt),
          _rStat(rStat),
          _fx(fx),
          _fy(fy),
          _fz(fz),
          _vsx(vsx),
          _vsy(vsy) {}

    // Copy constructor
    TMeasyState(const TMeasyState& other)
        : _xe(other._xe),
          _ye(other._ye),
          _xedot(other._xedot),
          _yedot(other._yedot),
          _omega(other._omega),
          _dOmega(other._dOmega),
          _xt(other._xt),
          _rStat(other._rStat),
          _fx(other._fx),
          _fy(other._fy),
          _fz(other._fz),
          _vsx(other._vsx),
          _vsy(other._vsy),
          _My(other._My),
          _engTor(other._engTor) {}

    // the actual state that are intgrated
    double _xe, _ye;        // long and lat tire deflection
    double _xedot, _yedot;  // long and lat tire deflection velocity
    double _omega;          // angular velocity of wheel
    double _dOmega;         // angular velocity dot

    // other "states" that we need to keep track of
    double _xt;            // vertical tire compression
    double _rStat;         // loaded tire radius
    double _fx, _fy, _fz;  // long, lateral and vertical force in tire frame

    // velocities in tire frame
    double _vsx, _vsy;

    double _My;  // Rolling resistance moment (negetive)

    // torque from engine that we keep track of
    double _engTor;
};

// TMeasy tire without relaxation
struct TMeasyNrParam {
    // default constructor just assigns zero to all members
    TMeasyNrParam()
        : _jw(6.69),
          _rr(0.015),
          _mu(0.8),
          _r0(0.4699),
          _width(0.245),
          _rim_radius(0.254),
          _pn(8562.8266),
          _pnmax(29969.893),
          _kt(411121.0),
          _rdyncoPn(0.375),
          _rdyncoP2n(0.75),
          _fzRdynco(0),
          _rdyncoCrit(0),
          _dfx0Pn(151447.29),
          _dfx0P2n(236412.79),
          _fxmPn(7575.3614),
          _fxmP2n(12808.276),
          _fxsPn(4657.9208),
          _fxsP2n(8625.3352),
          _sxmPn(0.12),
          _sxmP2n(0.15),
          _sxsPn(0.9),
          _sxsP2n(0.95),
          _dfy0Pn(50931.693),
          _dfy0P2n(94293.847),
          _fymPn(6615.0404),
          _fymP2n(12509.947),
          _fysPn(6091.5092),
          _fysP2n(11443.875),
          _symPn(0.38786),
          _symP2n(0.38786),
          _sysPn(0.82534),
          _sysP2n(0.91309),
          _vcoulomb(1.0),
          _frblend_begin(1.),
          _frblend_end(3.),
          _bearingCapacity(10000),
          _li(90),
          _p_li(1.),
          _p_use(1.) {}
    // copy constructor
    TMeasyNrParam(const TMeasyNrParam& other)
        : _jw(other._jw),
          _rr(other._rr),
          _mu(other._mu),
          _r0(other._r0),
          _width(other._width),
          _rim_radius(other._rim_radius),
          _pn(other._pn),
          _pnmax(other._pnmax),
          _kt(other._kt),
          _rdyncoPn(other._rdyncoPn),
          _rdyncoP2n(other._rdyncoP2n),
          _fzRdynco(other._fzRdynco),
          _rdyncoCrit(other._rdyncoCrit),
          _dfx0Pn(other._dfx0Pn),
          _dfx0P2n(other._dfx0P2n),
          _fxmPn(other._fxmPn),
          _fxmP2n(other._fxmP2n),
          _fxsPn(other._fxsPn),
          _fxsP2n(other._fxsP2n),
          _sxmPn(other._sxmPn),
          _sxmP2n(other._sxmP2n),
          _sxsPn(other._sxsPn),
          _sxsP2n(other._sxsP2n),
          _dfy0Pn(other._dfy0Pn),
          _dfy0P2n(other._dfy0P2n),
          _fymPn(other._fymPn),
          _fymP2n(other._fymP2n),
          _fysPn(other._fysPn),
          _fysP2n(other._fysP2n),
          _symPn(other._symPn),
          _symP2n(other._symP2n),
          _sysPn(other._sysPn),
          _sysP2n(other._sysP2n),
          _vcoulomb(other._vcoulomb),
          _frblend_begin(other._frblend_begin),
          _frblend_end(other._frblend_end),
          _bearingCapacity(other._bearingCapacity),
          _li(other._li),
          _p_li(other._p_li),
          _p_use(other._p_use) {}

    double _jw;          // wheel inertia
    double _rr;          // Rolling Resistance
    double _mu;          // Local friction coefficient between tire and road
    double _r0;          // unloaded tire radius
    double _width;       // tire width
    double _rim_radius;  // rim radius
    double _pn;          // nominal vertical force
    double _pnmax;       // max vertical force
    double _kt;          // vertical tire stiffness
    double _rdyncoPn;    // dynamic radius weighting coefficient at nominal load
    double _rdyncoP2n;   // dynamic radius weighting coefficient at max load
    double _fzRdynco;    // critical value for the vertical force
    double _rdyncoCrit;
    // Longitudinal
    double _dfx0Pn, _dfx0P2n;  // Initial longitudinal slopes dFx/dsx [N]
    double _fxmPn, _fxmP2n;    // Maximum longituidnal force [N]
    double _fxsPn, _fxsP2n;    // Longitudinal load at sliding [N]
    double _sxmPn, _sxmP2n;    // slip sx at maximum longitudinal load Fx
    double _sxsPn, _sxsP2n;    // slip sx where sliding begins
    // Lateral
    double _dfy0Pn, _dfy0P2n;  // intial lateral slopes dFx/dsx [N]
    double _fymPn, _fymP2n;    // maximum lateral force [N]
    double _fysPn, _fysP2n;    // Lateral load at sliding [N]
    double _symPn, _symP2n;    // slip sx at maximum lateral load Fx
    double _sysPn, _sysP2n;    // slip sx where sliding begins
    double _vcoulomb;          // Velocity below which we care about static friction
    double _frblend_begin;     // Beginning of friction blending
    double _frblend_end;       // End of friction blending
    double _bearingCapacity;   // High level tire parameters that define all other parameters that the user can set
    double _li;                // Load index
    double _p_li;              // Pressure at load index
    double _p_use;             // Pressure at which the tire is used
};

struct TMeasyNrState {
    TMeasyNrState()
        : _omega(0.),
          _dOmega(0),
          _xt(0.),
          _rStat(0.),
          _fx(0.),
          _fy(0.),
          _fz(0.),
          _vsx(0.),
          _vsy(0.),
          _My(0.),
          _engTor(0.) {}

    TMeasyNrState(double omega,
                  double dOmega,
                  double xt,
                  double rStat,
                  double fx,
                  double fy,
                  double fz,
                  double vsx,
                  double vsy,
                  double My,
                  double engTor)
        : _omega(omega),
          _dOmega(dOmega),
          _xt(xt),
          _rStat(rStat),
          _fx(fx),
          _fy(fy),
          _fz(fz),
          _vsx(vsx),
          _vsy(vsy),
          _My(My),
          _engTor(engTor) {}

    // Copy constructor
    TMeasyNrState(const TMeasyNrState& other)
        : _omega(other._omega),
          _dOmega(other._dOmega),
          _xt(other._xt),
          _rStat(other._rStat),
          _fx(other._fx),
          _fy(other._fy),
          _fz(other._fz),
          _vsx(other._vsx),
          _vsy(other._vsy),
          _My(other._My),
          _engTor(other._engTor) {}

    // Wheel states that are set as tire states
    double _omega;   // angular velocity of wheel
    double _dOmega;  // angular velocity dot

    // Other "states" that we need to keep track of
    double _xt;            // vertical tire compression
    double _rStat;         // loaded tire radius
    double _fx, _fy, _fz;  // long, lateral and vertical force in tire frame

    // Velocities in the tire frame
    double _vsx, _vsy;

    double _My;  // Rolling resistance moment (negetive)

    // Torque from engine that we keep track of
    double _engTor;
};

// vehicle Parameters structure
struct VehicleParam {
    // default constructor with pre tuned values from HMMVW calibration
    VehicleParam()
        : _a(1.6889),
          _b(1.6889),
          _h(0.713),
          _m(2097.85),
          _jz(4519.),
          _muf(127.866),
          _mur(129.98),
          _nonLinearSteer(false),
          _maxSteer(0.6525249),
          _crankInertia(1.1),
          _tcbool(false),
          _upshift_RPS(10000.),
          _downshift_RPS(0.),
          _maxBrakeTorque(4000.),
          _step(1e-2),
          _throttleMod(0),
          _driveType(1),
          _whichWheels(1) {}

    // constructor
    VehicleParam(double a,
                 double b,
                 double h,
                 double m,
                 double Jz,
                 double muf,
                 double mur,
                 bool steer_bool,
                 double maxSteer,
                 double crank_inertia,
                 bool tc_bool,
                 double upshift_RPS,
                 double downshift_RPS,
                 double brakeTorque,
                 double step,
                 bool throttle_mod,
                 bool driveType,
                 bool whichWheels)
        : _a(a),
          _b(b),
          _h(h),
          _m(m),
          _jz(Jz),
          _muf(muf),
          _mur(mur),
          _nonLinearSteer(steer_bool),
          _maxSteer(maxSteer),
          _crankInertia(crank_inertia),
          _tcbool(tc_bool),
          _upshift_RPS(upshift_RPS),
          _downshift_RPS(downshift_RPS),
          _maxBrakeTorque(brakeTorque),
          _step(step),
          _throttleMod(throttle_mod),
          _driveType(driveType),
          _whichWheels(whichWheels) {}

    // Copy constructor
    VehicleParam(const VehicleParam& other)
        : _a(other._a),
          _b(other._b),
          _h(other._h),
          _m(other._m),
          _jz(other._jz),
          _muf(other._muf),
          _mur(other._mur),
          _nonLinearSteer(other._nonLinearSteer),
          _maxSteer(other._maxSteer),
          _crankInertia(other._crankInertia),
          _tcbool(other._tcbool),
          _upshift_RPS(other._upshift_RPS),
          _downshift_RPS(other._downshift_RPS),
          _maxBrakeTorque(other._maxBrakeTorque),
          _step(other._step),
          _throttleMod(other._throttleMod),
          _driveType(other._driveType),
          _whichWheels(other._whichWheels),
          _steerMap(other._steerMap),
          _gearRatios(other._gearRatios),
          _powertrainMap(other._powertrainMap),
          _lossesMap(other._lossesMap),
          _CFmap(other._CFmap),
          _TRmap(other._TRmap),
          _shiftMap(other._shiftMap) {}

    double _a, _b;      // distance c.g. - front axle & distance c.g. - rear axle (m)
    double _h;          // height of c.g
    double _m;          // total vehicle mass (kg)
    double _jz;         // yaw moment inertia (kg.m^2)
    double _muf, _mur;  // front and rear unsprung mass

    // Bool that checks if the steering is non linea ---> Need to depricate
    // this, can always define a steer map 1 -> Steering is non linear, requires
    // a steering map defined - example in json 0 -> Steering is linear. Need
    // only a max steer defined. The normalized sterring then just multiplies
    // against this value to give a wheel angle
    bool _nonLinearSteer;
    // Non linear steering map in case the steering mechanism is not linear
    std::vector<MapEntry> _steerMap;
    // max steer angle parameters of the vehicle
    double _maxSteer;

    // crank shaft inertia
    double _crankInertia;
    double _upshift_RPS;
    double _downshift_RPS;
    // some gear parameters
    std::vector<double> _gearRatios;  // gear ratio

    // boolean for torque converter presense
    bool _tcbool;

    // double _maxTorque; // Max torque
    double _maxBrakeTorque;  // max brake torque

    double _step;  // vehicle integration time step

    // Bool that defines how the throttle modulates the maps
    // 1 -> Modulates like in a motor -> Modifies the entire torque and RPM map
    // 0 -> Modulates like in an engine -> multiplies only against the torque -
    // > Default
    bool _throttleMod;
    // We will always define the powertrain with a map
    std::vector<MapEntry> _powertrainMap;
    std::vector<MapEntry> _lossesMap;

    // torque converter maps
    std::vector<MapEntry> _CFmap;  // capacity factor map
    std::vector<MapEntry> _TRmap;  // Torque ratio map

    // Flag for wether we have an 4WD or 2WD
    // 1-> 4WD - This is the default
    // 0 -> 2WD - To set this, the JSON entry needs to be added.
    bool _driveType;

    // If we have a 2WD vehicle this bool specifies which of the 2 wheels are
    // powered 1 -> Rear wheels are powered 0 -> Front wheels are powered
    bool _whichWheels;

    // Additionally we have a shift map that needs to always be filled,
    // This can either be filled by setting the same upshift and downshift RPM
    // for all the gears or by setting upshift and downshift RPM for each of the
    // gears
    std::vector<MapEntry> _shiftMap;
};

// vehicle states structure
struct VehicleState {
    // default constructor just assigns zero to all members
    VehicleState()
        : _x(0.),
          _y(0.),
          _dx(0),
          _dy(0),
          _u(0.),
          _v(0.),
          _psi(0.),
          _wz(0.),
          _udot(0.),
          _vdot(0.),
          _wzdot(0.),
          _tor(0.),
          _crankOmega(0.),
          _dOmega_crank(0.),
          _current_gr(0) {}

    // copy constructor
    VehicleState(const VehicleState& other)
        : _x(other._x),
          _y(other._y),
          _dx(other._dx),
          _dy(other._dy),
          _u(other._u),
          _v(other._v),
          _psi(other._psi),
          _wz(other._wz),
          _udot(other._udot),
          _vdot(other._vdot),
          _wzdot(other._wzdot),
          _tor(other._tor),
          _crankOmega(other._crankOmega),
          _dOmega_crank(other._dOmega_crank),
          _current_gr(other._current_gr) {}

    // special constructor in case need to start simulation
    // from some other state
    double _x, _y;     // x and y position
    double _dx, _dy;   // This is basically u and v but transformed to global coordinates
    double _u, _v;     // x and y velocity
    double _psi, _wz;  // yaw angle and yaw rate

    // acceleration 'states'
    double _udot, _vdot;
    double _wzdot;

    // crank torque (used to transmit torque to tires) and crank angular
    // velocity state
    double _tor;
    double _crankOmega;
    double _dOmega_crank;
    int _current_gr;
};

// ------------------------------ Vehicle functions

double driveTorque(const VehicleParam& v_params, const double throttle, const double omega);

inline double brakeTorque(const VehicleParam& v_params, const double brake) {
    return v_params._maxBrakeTorque * brake;
}
void differentialSplit(double torque,
                       double max_bias,
                       double speed_rear,
                       double speed_front,
                       double& torque_rear,
                       double& torque_front,
                       bool split,
                       bool whichWheels);

// setting vehicle parameters using a JSON file
void setVehParamsJSON(VehicleParam& v_params, const char* fileName);

void vehToTireTransform(TMeasyState& tiref_st,
                        TMeasyState& tirer_st,
                        const VehicleState& v_states,
                        const std::vector<double>& loads,
                        const VehicleParam& v_params,
                        double steering);

void vehToTireTransform(TMeasyNrState& tiref_st,
                        TMeasyNrState& tirer_st,
                        const VehicleState& v_states,
                        const std::vector<double>& loads,
                        const VehicleParam& v_params,
                        double steering);

void tireToVehTransform(TMeasyState& tiref_st,
                        TMeasyState& tirer_st,
                        const VehicleState& v_states,
                        const VehicleParam& v_params,
                        double steering);

void tireToVehTransform(TMeasyNrState& tiref_st,
                        TMeasyNrState& tirer_st,
                        const VehicleState& v_states,
                        const VehicleParam& v_params,
                        double steering);

// ------------------------------ Tire functions

// sets the vertical tire deflection based on the vehicle weight
// template based on which tire
void tireInit(TMeasyParam& t_params);
void tireInit(TMeasyNrParam& t_params);

// function to calculate the force from the force charactristics
// used by tireSync
void tmxy_combined(double& f, double& fos, double s, double df0, double sm, double fm, double ss, double fs);
// Force function required by the TMeasy tire with no relaxation
void computeCombinedColumbForce(double& fx, double& fy, double mu, double vsx, double vsy, double fz, double vcoulomb);
// setting tire parameters using a JSON file
void setTireParamsJSON(TMeasyParam& t_params, const char* fileName);
void setTireParamsJSON(TMeasyNrParam& t_params, const char* fileName);

// Functions used in the RHS function for the external solver
void computeTireLoads(std::vector<double>& loads,
                      const VehicleState& v_states,
                      const VehicleParam& v_params,
                      const TMeasyParam& t_params);
void computeTireLoads(std::vector<double>& loads,
                      const VehicleState& v_states,
                      const VehicleParam& v_params,
                      const TMeasyNrParam& t_params);

void computeTireRHS(TMeasyState& t_states, const TMeasyParam& t_params, const VehicleParam& v_params, double steering);
void computeTireRHS(TMeasyNrState& t_states,
                    const TMeasyNrParam& t_params,
                    const VehicleParam& v_params,
                    double steering);
void computePowertrainRHS(VehicleState& v_states,
                          TMeasyState& tiref_st,
                          TMeasyState& tirer_st,
                          const VehicleParam& v_params,
                          const TMeasyParam& t_params,
                          const DriverInput& controls);
void computePowertrainRHS(VehicleState& v_states,
                          TMeasyNrState& tiref_st,
                          TMeasyNrState& tirer_st,
                          const VehicleParam& v_params,
                          const TMeasyNrParam& t_params,
                          const DriverInput& controls);
void computeVehRHS(VehicleState& v_states,
                   const VehicleParam& v_params,
                   const std::vector<double>& fx,
                   const std::vector<double>& fy);

double GetTireMaxLoad(unsigned int li);
// Functions to guess tire parameters from general tire specs
void GuessTruck80Par(unsigned int li,
                     double tireWidth,
                     double ratio,
                     double rimDia,
                     double pinfl_li,
                     double pinfl_use,
                     TMeasyNrParam& t_params);

void GuessTruck80Par(double tireLoad,
                     double tireWidth,
                     double ratio,
                     double rimDia,
                     double pinfl_li,
                     double pinfl_use,
                     TMeasyNrParam& t_params);

void GuessPassCar70Par(unsigned int li,
                       double tireWidth,
                       double ratio,
                       double rimDia,
                       double pinfl_li,
                       double pinfl_use,
                       TMeasyNrParam& t_params);

void GuessPassCar70Par(double tireLoad,
                       double tireWidth,
                       double ratio,
                       double rimDia,
                       double pinfl_li,
                       double pinfl_use,
                       TMeasyNrParam& t_params);

}  // namespace d11

#endif
