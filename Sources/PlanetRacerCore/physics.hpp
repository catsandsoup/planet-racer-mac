// Soft-body car + ground, ported 1:1 from the original ActionScript (frame 175: Verlet,
// collide, rollWheel, aF, lean, generateTerrain). One step() == one original 36 fps frame.
#pragma once
#include "data.hpp"
#include <deque>
#include <functional>
#include <random>
#include <vector>

struct Rng {
    std::mt19937 gen{std::random_device{}()};
    double unit() { return std::uniform_real_distribution<double>(0.0, 1.0)(gen); } // Math.random()
    int below(int n) { return n <= 0 ? 0 : int(unit() * n); }                       // random(n)
};

struct Segment { double x0, y0, x1, y1; };

class Terrain {
public:
    std::deque<Segment> segs;
    bool handmade = false;
    bool flatTerrain = false; // set near the finish: generator only emits flat 300-unit pieces

    void initRaceStart();                      // the fixed start strip from initVehicle()
    void initFromPoints(const std::vector<std::pair<double, double>>& pts);
    void initFlat(double y, double x0, double x1);
    // generateTerrain(): extend to the right of 'needX', drop pieces left of 'dropX'
    void generate(double needX, double dropX, double surface, Rng& rng);
    double groundY(double x) const;
    const Segment& last() const { return segs.back(); }

private:
    int tMode = 0, terrainStep = 0, tSteps = 0;
    bool finishMode = false;
    void generateOne(double surface, Rng& rng);
};

struct WheelRim { double x = 0, y = 0, ox = 0, oy = 0, rL = 0, s = 0, w = 0; };

struct MassPoint {
    double x = 0, y = 0, ox = 0, oy = 0, r = 0, g = 0;
    bool collide = true, hasWheel = false;
    WheelRim wheel;
};

struct Spring { int a, b; double rL, w0, w1; bool alive = true; };

class SoftCar {
public:
    std::vector<MassPoint> p;
    std::vector<Spring> springs;
    const CarDef* def = nullptr;
    int rear = 0, front = 1; // indices of the two wheel points

    // swapRadii: the opponent car is built mirrored (front radius on point 0)
    void build(const CarDef& d, double initX, double initY, double grav, bool swapRadii);
    void step(double drag);                                // Verlet()
    // collide(): f = tire grip (velocity damping on contact); onHit gets (point index, penetration)
    void collide(const Terrain& t, double f, const std::function<void(int, double)>& onHit);
    void spin(double add, double maxSpeed);                // move(): add to wheel drive
    void lean(int dir, double riderPower);                 // lean()
    void push(double dx, int from, int to);                // afterburner nudge
    void wreck(double grav);                               // crashCar() physics part
    double angleAt(const AngleCheck& a) const;             // angleConstrain() helper, degrees
    double bodyAngle() const;                              // chassis._rotation (degrees)
    void bodyCenter(double& x, double& y) const;           // chassis._x/_y
    void trackCenter(double& x, double& y) const;          // carX/carY
    static void rollWheel(MassPoint& p, double nx, double ny);
};
