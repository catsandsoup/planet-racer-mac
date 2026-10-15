#include "race.hpp"
#include <algorithm>
#include <cmath>

static constexpr double kPi = 3.141592653589793;
static constexpr double kStarMargin = 100;

void Race::begin(const GameData& d, const RaceSetup& s) {
    *this = Race();
    data = &d;
    setup = s;
    const Planet& pl = *s.planet;
    grav = pl.gravity;

    if (!pl.mapPoints.empty()) terrain.initFromPoints(pl.mapPoints);
    else terrain.initRaceStart();

    // init(): player spawns at (300,230), opponent at (150,230) on the 380-high start strip
    double lift = terrain.groundY(340) - 380;
    car.build(d.car, 300, 230 + lift, grav, false);
    opp.build(d.car, 150, 230 + lift, grav, true);

    // setupVehicle(): wear makes parts weaker, (100 - wear/2)%
    const Parts& P = d.parts;
    auto loss = [](double wear) { return (100 - wear / 2) / 100; };
    const EnginePart& e = P.engines[s.engine];
    const ChassisPart& c = P.chassis[s.chassis];
    topSpeed = std::min(1.4 * e.speed * loss(s.engineWear) * c.speed * loss(s.chassisWear), kMaxSpeed);
    f = P.tires[s.tires].grip * loss(s.tireWear);
    engineSound = e.sound;

    double rep = s.kingOpponent ? 100 : 40 + 3.0 * (s.opponent ? s.opponent->rep : 50) / 5;
    oppTopSpeed = 1.4 * ((rep - 50) / 150 + 1);

    // initAfterburner("measure"): 33 frames of boost per second of tank
    boostTotal = int(P.afterburners[s.afterburner].seconds * 33);
    boostLeft = int(boostTotal - s.afterburnerWear / 100 * boostTotal);
    if (s.playerKing) { // the kingmobile: no wear, 2.4 x 2.4 power, glue tires, a 50 s tank
        topSpeed = std::min(1.4 * 2.4 * 2.4, kMaxSpeed);
        f = 0.001;
        boostTotal = boostLeft = 1650;
        engineSound = 3;
    }

    longRandom = rng.unit();
    medRandom = rng.unit();
    updateCamera();
    terrain.generate(camX + viewW + 340, camX - 600, pl.surface, rng);
    updateStars(true);
}

void Race::start() {
    if (started) return;
    started = true;
    events.push_back({Sfx::StartRace});
}

RaceResult Race::result() const {
    // finishing beats crashing: the original's finish message replaces the crash message
    if (finished) return raceWon == 1 ? RaceResult::Won : RaceResult::Lost;
    if (crashed) return RaceResult::Crashed;
    return RaceResult::Running;
}

void Race::tick(const RaceInput& in) {
    const Planet& pl = *setup.planet;
    if (started) {
        if (!crashed && !finished) move(in);
        else engineOn = false;
        car.step(kDrag);
        if (oppVisible) opp.step(kDrag);
        raceTime += kTick;
    }
    afterburner(in);

    telrun++; telLong++;
    if (telLong > 4) {
        terrain.generate(camX + viewW + 340, camX - 600, pl.surface, rng);
        telLong = 0;
        if (!crashed) angleConstrain();
        else musicFade = std::max(0.0, musicFade - 0.01);
    }
    startBuildings = camX < 1400;
    if (telrun > 3) {
        if (started) calcOppPos();
        if (!finished) calcPlanetPos();
        else musicFade = std::max(0.0, musicFade - 0.01);
        telrun = 0;
    }

    car.collide(terrain, f, [this](int i, double pen) { if (started && !finished) setDamage(i, pen); });
    hitGroundCounter--;
    if (oppVisible) {
        opp.collide(terrain, f, nullptr);
        if (!oppFinished) opp.spin(-oppTopSpeed, kMaxSpeed); // moveOpp(): drives the other way round
    }

    updateCamera();
    updateStars(false);
    damageFlash = damageFlash > 3 ? damageFlash - 3 : 0;

    // the original's setInterval timers, run on game time so pausing freezes them too
    t100 += kTick; t1000 += kTick; t6000 += kTick;
    while (t100 >= 0.1) {
        t100 -= 0.1;
        if (!finished) renderSurfaceTiles();
        if (damage > 100) { crashed = true; damage = 100; } // manageDamage()
    }
    while (t1000 >= 1.0) { t1000 -= 1.0; medRandom = rng.unit(); }
    while (t6000 >= 6.0) {
        t6000 -= 6.0;
        longRandom = rng.unit();
        if (longRandom < 0.4) events.push_back({Sfx::Ambient, 0.4f});
    }
}

void Race::move(const RaceInput& in) {
    double v = 0;
    if (in.left) car.lean(-1, kRiderPower);
    if (in.right) car.lean(1, kRiderPower);
    engineOn = in.up;
    if (in.up) v += topSpeed;
    if (in.down) v -= topSpeed;
    car.spin(v, kMaxSpeed);
}

void Race::afterburner(const RaceInput& in) {
    boosting = false;
    if (started && in.boost && boostLeft > 0) {
        boostLeft--;
        boosting = true;
        double dx = 2 * std::cos(car.bodyAngle() * kPi / 180) / 10;
        car.push(dx, 0, int(car.p.size()));
    }
    if (!oppVisible) return;
    if (oppGear == 0) oppBurning = !oppOverStart && countOS > 4;
    else {
        if (!oppFinished && oppOverStart && longRandom > 0.3) oppBurning = true;
        if (oppFinished) oppBurning = false;
    }
    if (oppBurning) opp.push(-0.36, 2, 6);
}

void Race::angleConstrain() {
    const CarDef& d = *car.def;
    double a = car.angleAt(d.ko);
    bool ok = (a > d.ko.min && a < d.ko.max) || (a > d.ko.min - 360 && a < d.ko.max - 360);
    telKO = ok ? 0 : telKO + 1;
    if (telKO > 3 || car.angleAt(d.flip) < d.flip.min) crashCar();
}

void Race::crashCar() {
    if (wrecked) return;
    wrecked = true;
    car.wreck(grav);
    crashed = true;
    f = 0.1;
    engineOn = false;
    events.push_back({Sfx::Crash});
}

void Race::setDamage(int point, double pen) {
    double v = std::min(std::fabs(pen), 50.0);
    if (v <= 0) return;
    v = v * v * v / 1000;
    bool wheel = car.p[point].hasWheel;
    if (wheel) {
        v /= 5;
        if (v > 0.15 && hitGroundCounter <= 0) {
            hitGroundCounter = 5;
            events.push_back({Sfx::HitGround, float(std::min(200 * v, 100.0) / 100)});
        }
    } else if (v > 0.15 && hitGroundCounter <= 0) {
        hitGroundCounter = 5;
        events.push_back({Sfx::HitRoof, float(std::min(400 * v, 100.0) / 100)});
    }
    if (v > 0.1) damageFlash = std::min(v * 100, 100.0);
    if (wheel) wheelDamage += v; else damage += v;
}

void Race::calcOppPos() {
    const Planet& pl = *setup.planet;
    const double step = 4;
    if (!firstOppCalc) {
        firstOppCalc = true;
        double diffFactor = 1 + (setup.difficulty - 1) / 5;
        double k = pl.difficulty * ((1 + diffFactor) / 2);
        surfaceFactor = pl.surface / 100;
        surfaceFluct = surfaceFactor + 0.5;
        oppMaxSpeed = 11 * k * oppTopSpeed;
        oppMinSpeed = 4 * k * oppTopSpeed;
    }
    if (!terrain.flatTerrain && opp.p[1].x < 0) { oppOverStart = true; oppVisible = false; }

    if (!oppFinished) {
        if (oppGear == 0) {
            countOS += step;
            if (countOS > 20) oppSpeed += 5.6;
            if (oppSpeed >= oppMaxSpeed * 0.7) { oppGear = 1; countOS = 0; }
        } else {
            countOS -= step;
            if (countOS <= 0) { oppSpeed += (2 + medRandom * 4) * surfaceFluct; countOS = 8 + rng.below(30); }
            if (rng.unit() < 0.01 * surfaceFactor) oppSpeed = rng.below(4);
            if (oppSpeed > oppMaxSpeed) oppSpeed = oppMaxSpeed - 1;
            else if (oppSpeed < oppMinSpeed) oppSpeed += 0.1;
            if (longRandom < 0.004 && oppXPos < pl.size * 0.7 && oppXPos > pl.size * 0.2 && !setup.kingOpponent)
                oppCrashed = true;
        }
        if (!oppCrashed) oppXPos += oppSpeed * step;
    }

    if (!oppVisible) {
        if (oppXPos - 50 > pl.size && !oppFinished) {
            oppFinished = true;
            if (raceWon < 0) raceWon = 0;
        }
    } else if (oppOverStart && !oppFinished) {
        double ox, oy;
        opp.trackCenter(ox, oy);
        if (ox < pl.size) { oppFinished = true; if (raceWon < 0) raceWon = 0; }
    }

    // bring the opponent back on screen near the finish, arriving from the far side
    const Segment& L = terrain.last();
    bool lastFlat = terrain.flatTerrain && L.y0 == L.y1;
    if (lastFlat && camX > pl.size - 1500 && !oppVisible &&
        (oppXPos >= pl.size - 275 || oppFinished) && (oppXPos <= L.x1 || oppFinished)) {
        double nwPos;
        if (oppFinished) nwPos = pl.size - 200 < L.x1 ? pl.size - 200 : L.x1 - 100;
        else if (oppXPos > pl.size) nwPos = pl.size - 100;
        else if (L.x1 < pl.size + 275) nwPos = L.x1;
        else nwPos = pl.size + 275;
        double lift = 8 + rng.below(8);
        double gy = terrain.groundY(nwPos + 40);
        double v = oppFinished ? 2 : 10;
        for (size_t i = 0; i < opp.p.size(); i++) {
            MassPoint& mp = opp.p[i];
            mp.x = nwPos + car.def->points[i].x;
            mp.y = gy - lift + car.def->points[i].y;
            mp.ox = mp.x + v; mp.oy = mp.y;
            if (mp.hasWheel) mp.wheel.s = -v;
        }
        oppVisible = true;
    }
}

void Race::calcPlanetPos() {
    const Planet& pl = *setup.planet;
    if (camX > pl.size - 2400) terrain.flatTerrain = true;
    if (camX > pl.size - viewW / 2) stopScroll = true;
    double bx, by;
    car.bodyCenter(bx, by);
    if (bx + 50 > pl.size) { // no crash guard in the original: a wreck sliding over the line finishes
        finished = true;
        engineOn = false;
        if (raceWon < 0) raceWon = 1;
        events.push_back({raceWon == 1 ? Sfx::Finish : Sfx::Lose});
    }
}

void Race::updateCamera() {
    if (!crashed) car.trackCenter(carX, carY);
    else { carX = (car.p[4].x + car.p[5].x) / 2; carY = (car.p[4].y + car.p[5].y) / 2; }
    double nx = carX - viewW / 3, ny = carY - viewH / 2;
    camDX = camDY = 0;
    if (!stopScroll) {
        camDX = nx - camX; camDY = ny - camY;
        if (std::fabs(camDX) < 0.5) camDX = 0;
        if (std::fabs(camDY) < 0.5) camDY = 0;
        camX = nx; camY = ny;
    }
}

void Race::updateStars(bool initial) {
    auto spawn = [this](double x, double y) {
        stars.push_back({x, y, rng.below(2) + 1, 0.9 + rng.unit() * 0.09});
    };
    if (initial) {
        stars.clear();
        for (int i = 0; i < 19; i++) spawn(rng.below(int(viewW)), rng.below(int(viewH)));
        return;
    }
    if (stopScroll) return;
    for (auto& s : stars) { s.x -= camDX * (1 - s.distance); s.y -= camDY * (1 - s.distance); }
    stars.erase(std::remove_if(stars.begin(), stars.end(), [this](const Star& s) {
        return s.x < -kStarMargin || s.x > viewW + kStarMargin || s.y < 0 || s.y > viewH;
    }), stars.end());
    if (stars.size() < 18 && rng.unit() > 0.8) spawn(viewW + rng.below(int(kStarMargin)), rng.below(int(viewH)));
}

void Race::renderSurfaceTiles() {
    tiles.erase(std::remove_if(tiles.begin(), tiles.end(), [this](const SurfaceTile& t) {
        return t.x + 96.5 < camX;
    }), tiles.end());
    countTiles--;
    if (tiles.size() >= 2 || countTiles > 0) return;
    const Segment& L = terrain.last();
    double bottom = camY + viewH;
    if (L.y0 != 0 && L.y1 < bottom - 100 && L.x0 > camX + 270 && L.x1 - L.x0 > 50) {
        countTiles = 40 + rng.below(20);
        tiles.push_back({L.x0, (L.y0 + L.y1) / 2 + 140 + rng.below(60), rng.below(4) + 1});
    }
}
