// One head-to-head race, ported from the original mainLoop() and its helpers.
// tick() advances exactly one original frame (1/36 s). No rendering or audio here:
// the race reports what happened through `events` and public state.
#pragma once
#include "data.hpp"
#include "physics.hpp"
#include <string>
#include <vector>

struct RaceInput { bool up = false, down = false, left = false, right = false, boost = false; };

struct RaceSetup {
    const Planet* planet = nullptr;
    const Opponent* opponent = nullptr;
    int engine = 0, tires = 0, chassis = 0, afterburner = 0, color = 1; // indices into Parts (color 1-based)
    double engineWear = 0, chassisWear = 0, tireWear = 0, afterburnerWear = 0; // 0..100
    int oppChassis = 0, oppTires = 0, oppColor = 1;
    double difficulty = 1;   // 0 easy, 1 medium, 2 hard (the original _global.difficulty)
    bool kingOpponent = false;
    bool playerKing = false; // you are the King: the kingmobile (youKing in the original)
    std::string betLabel = "QUICK RACE";
};

enum class Sfx { StartRace, HitGround, HitRoof, Crash, Finish, Lose, Ambient };
struct SfxEvent { Sfx id; float volume = 1; };

struct SurfaceTile { double x, y; int frame; };
struct Star { double x, y; int frame; double distance; }; // screen-space, like the original

enum class RaceResult { Running, Won, Lost, Crashed };

class Race {
public:
    // tuning constants from init()
    static constexpr double kDrag = 0.9999999, kMaxSpeed = 2.7, kRiderPower = 0.6, kTick = 1.0 / 36.0;

    RaceSetup setup;
    const GameData* data = nullptr;
    Terrain terrain;
    SoftCar car, opp;
    Rng rng;

    // view (game units). The app sets these each frame from the window aspect.
    double viewW = 550, viewH = 400;
    double camX = 0, camY = 0, camDX = 0, camDY = 0;

    bool started = false, crashed = false, finished = false, stopScroll = false;
    bool oppVisible = true, oppOverStart = false, oppFinished = false, oppCrashed = false, oppBurning = false;
    int raceWon = -1; // -1 undecided, 0 opponent first, 1 player first
    double damage = 0, wheelDamage = 0, damageFlash = 0;
    int boostTotal = 0, boostLeft = 0;
    bool boosting = false, engineOn = false;
    double oppXPos = 0;          // opponent distance travelled around the planet (ghost)
    double carX = 0, carY = 0;   // camera focus (carX/carY)
    double raceTime = 0;
    int engineSound = 1;
    bool startBuildings = true;
    std::vector<SurfaceTile> tiles;
    std::vector<Star> stars;
    std::vector<SfxEvent> events;
    double musicFade = 1;        // fadeLoop(): race music fades after a crash/finish

    void begin(const GameData& d, const RaceSetup& s);
    void start();                // "press any key"
    void abandon() { crashCar(); } // the HUD's EXIT
    void tick(const RaceInput& in);
    RaceResult result() const;
    double grip() const { return f; }

private:
    bool wrecked = false;
    double grav = 0.24, f = 0.02, topSpeed = 1, oppTopSpeed = 1;
    int telrun = 0, telLong = 0, telKO = 0, hitGroundCounter = 0, countTiles = 0;
    double longRandom = 0.5, medRandom = 0.5;
    double t100 = 0, t1000 = 0, t6000 = 0;
    // opponent ghost (calcOppPos)
    bool firstOppCalc = false;
    int oppGear = 0;
    double oppSpeed = 0, countOS = 0, oppMaxSpeed = 0, oppMinSpeed = 0, surfaceFactor = 0, surfaceFluct = 0;

    void move(const RaceInput& in);
    void afterburner(const RaceInput& in);
    void angleConstrain();
    void crashCar();
    void setDamage(int point, double pen);
    void calcOppPos();
    void calcPlanetPos();
    void updateCamera();
    void updateStars(bool initial);
    void renderSurfaceTiles();
};
