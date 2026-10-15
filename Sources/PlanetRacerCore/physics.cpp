#include "physics.hpp"
#include <algorithm>
#include <cmath>

static constexpr double kPi = 3.141592653589793;
static constexpr double kMaxStep = 14; // per-frame velocity clamp from Verlet()

// ---------------------------------------------------------------- terrain

void Terrain::initRaceStart() {
    segs = {{-300, 380, 1000, 380}, {1000, 380, 1050, 390}, {1050, 390, 1380, 360},
            {1380, 360, 2000, 320}, {2000, 320, 2200, 270}, {2200, 270, 2300, 220}};
    handmade = false; flatTerrain = false; finishMode = false; tMode = 0; terrainStep = 0;
}

void Terrain::initFromPoints(const std::vector<std::pair<double, double>>& pts) {
    segs.clear();
    for (size_t i = 1; i < pts.size(); i++)
        if (pts[i].first > pts[i - 1].first)
            segs.push_back({pts[i - 1].first, pts[i - 1].second, pts[i].first, pts[i].second});
    // run-off so there is always flat ground past the last authored point
    double x = segs.back().x1, y = segs.back().y1;
    segs.push_back({x, y, x + 4000, y});
    handmade = true;
}

void Terrain::initFlat(double y, double x0, double x1) {
    segs = {{x0, y, x1, y}};
    handmade = true;
}

double Terrain::groundY(double x) const {
    for (auto& s : segs)
        if (x >= s.x0 && x <= s.x1) return s.y0 + (s.y1 - s.y0) * (x - s.x0) / std::max(1e-9, s.x1 - s.x0);
    return x < segs.front().x0 ? segs.front().y0 : segs.back().y1;
}

void Terrain::generate(double needX, double dropX, double surface, Rng& rng) {
    if (handmade) return;
    while (segs.size() > 2 && segs.front().x1 < dropX) segs.pop_front();
    // The original added one piece every 5 frames; we fill the (possibly much wider) view in one go.
    int guard = 0;
    while (segs.back().x1 < needX && guard++ < 200) generateOne(surface, rng);
}

void Terrain::generateOne(double surface, Rng& rng) {
    const Segment L = segs.back();
    if (terrainStep <= 0) {
        if (flatTerrain) finishMode = true;
        else if (tMode == 2) tMode = 3;
        else if (tMode == 4) tMode = 1;
        else {
            double r = rng.unit();
            tMode = r < 0.06 ? 4 : r < 0.1 ? 2 : r < 0.14 ? 5 : 0;
        }
        if (!finishMode && tMode != 0) { tSteps = terrainStep = rng.below(6) + 4; }
    }
    double r5 = 1.7 - rng.unit() * 1.4, r6 = 1.7 - rng.unit() * 1.4;
    double r21 = (r5 + 1) / 2, r18 = (r6 + 1) / 2;
    double k = surface / 100.0;
    double x = L.x1, y = L.y1;
    if (finishMode) { segs.push_back({x, y, x + 300, y}); return; }
    switch (tMode) {
    case 0: {
        const Segment& P = segs.size() > 1 ? segs[segs.size() - 2] : L;
        double prevSlope = (P.y1 - P.y0) / (P.x1 - P.x0);
        double x1 = x + 20 + rng.below(100);
        double y1 = y + 60 - rng.below(140);
        double slope = (y1 - y) / (x1 - x);
        double lim = 0.6 * k;
        if (prevSlope - slope > lim) slope = prevSlope - lim;
        else if (prevSlope - slope < -lim) slope = prevSlope + lim;
        segs.push_back({x, y, x1, y + (x1 - x) * slope});
        break;
    }
    case 1: segs.push_back({x, y, x + 35 + 65 * r5, y + terrainStep * (16 * k * r6)}); terrainStep--; break;
    case 2: segs.push_back({x, y, x + 35 + 65 * r5, y - (tSteps - terrainStep) * (16 * k * r6)}); terrainStep--; break;
    case 3: segs.push_back({x, y, x + 30 + 80 * r5, y - terrainStep * (16 * k * r6)}); terrainStep--; break;
    case 4: segs.push_back({x, y, x + 30 + 80 * r5, y + (tSteps - terrainStep) * (16 * k * r6)}); terrainStep--; break;
    case 5: segs.push_back({x, y, x + 26 + 40 * r21, y - (tSteps - terrainStep) * (14 * k * r18)}); terrainStep--; break;
    }
}

// ---------------------------------------------------------------- car

void SoftCar::build(const CarDef& d, double initX, double initY, double grav, bool swapRadii) {
    def = &d;
    p.clear(); springs.clear();
    bool sawRear = false, sawFront = false;
    for (size_t i = 0; i < d.points.size(); i++) {
        const CarPoint& cp = d.points[i];
        MassPoint m;
        m.x = cp.x + initX; m.y = cp.y + initY; m.ox = m.x; m.oy = m.y;
        m.g = grav * cp.gravityMul; m.collide = cp.collide;
        if (cp.wheel) {
            bool isRear = cp.wheel == 1;
            double r = (isRear != swapRadii) ? d.rearRadius : d.frontRadius;
            m.r = r; m.hasWheel = true;
            m.wheel.x = r; m.wheel.y = 0; m.wheel.ox = r; m.wheel.oy = 0; m.wheel.rL = r; m.wheel.s = 0; m.wheel.w = 0;
            if (isRear && !sawRear) { rear = int(i); sawRear = true; }
            if (!isRear && !sawFront) { front = int(i); sawFront = true; }
        }
        p.push_back(m);
    }
    for (auto& s : d.springs) {
        double dx = p[s.first].x - p[s.second].x, dy = p[s.first].y - p[s.second].y;
        springs.push_back({s.first, s.second, std::sqrt(dx * dx + dy * dy), d.stiffness, d.stiffness, true});
    }
}

static inline double clampd(double v, double lo, double hi) { return std::max(lo, std::min(hi, v)); }

void SoftCar::step(double drag) {
    for (auto& mp : p) {
        if (!mp.hasWheel) continue;
        WheelRim& w = mp.wheel;
        double nx = -w.y, ny = w.x, l = std::sqrt(nx * nx + ny * ny);
        nx /= l; ny /= l;
        w.x += w.s * nx; w.y += w.s * ny;
        double oldx = w.ox, oldy = w.oy;
        w.ox = w.x; w.oy = w.y;
        double vx = clampd(w.x - oldx, -kMaxStep, kMaxStep), vy = clampd(w.y - oldy, -kMaxStep, kMaxStep);
        w.x += drag * vx; w.y += drag * vy;
        double d = std::sqrt(w.x * w.x + w.y * w.y), k = (d - w.rL) / d;
        w.x -= w.x * k; w.y -= w.y * k;
    }
    for (auto& mp : p) {
        double oldx = mp.ox, oldy = mp.oy;
        mp.ox = mp.x; mp.oy = mp.y;
        double vx = clampd(mp.x - oldx, -kMaxStep, kMaxStep), vy = clampd(mp.y - oldy, -kMaxStep, kMaxStep);
        mp.x += drag * vx; mp.y += drag * vy + mp.g;
    }
    for (auto& s : springs) {
        if (!s.alive) continue;
        MassPoint &a = p[s.a], &b = p[s.b];
        double dx = a.x - b.x, dy = a.y - b.y, d = std::sqrt(dx * dx + dy * dy);
        if (d < 1e-9) continue;
        double k = (d - s.rL) / d, k0 = k * s.w0, k1 = k * s.w1;
        a.x -= dx * k0; a.y -= dy * k0;
        b.x += dx * k1; b.y += dy * k1;
    }
}

void SoftCar::rollWheel(MassPoint& mp, double nx, double ny) {
    nx = clampd(nx, -1, 1); ny = clampd(ny, -1, 1);
    WheelRim& w = mp.wheel;
    double tx = -w.y, ty = w.x, l = std::sqrt(tx * tx + ty * ty);
    tx /= l; ty /= l;
    double vx = (mp.x - mp.ox) + tx * w.s, vy = (mp.y - mp.oy) + ty * w.s;
    double along = -ny * vx + nx * vy;
    w.ox = w.x - along * tx; w.oy = w.y - along * ty;
    double w0 = 1 - w.w;
    mp.x += w0 * w.s * -ny; mp.y += w0 * w.s * nx;
    w.s *= w.w;
}

static inline void applyFriction(MassPoint& mp, double f) { // aF(p, 1)
    mp.ox += f * (mp.x - mp.ox);
    mp.oy += f * (mp.y - mp.oy);
}

void SoftCar::collide(const Terrain& t, double f, const std::function<void(int, double)>& onHit) {
    for (size_t i = 0; i < p.size(); i++) {
        MassPoint& mp = p[i];
        if (!mp.collide) continue;
        // the original samples the position once, before testing every segment
        const double px = mp.x, py = mp.y, r = mp.r;
        for (const Segment& s : t.segs) {
            if (!(px <= s.x1 && px >= s.x0)) continue;
            double dx = s.x1 - s.x0, dy = s.y1 - s.y0, len = std::sqrt(dx * dx + dy * dy);
            double ux = dx / len, uy = dy / len, nX = -uy, nY = ux;
            double rx = px - s.x0, ry = py - s.y0, along = rx * ux + ry * uy;
            if (along < 0 || len < along) {
                if (len < along) { rx -= dx; ry -= dy; }
                double dist = std::sqrt(rx * rx + ry * ry), pen = r - dist;
                if (pen > 0) {
                    mp.x += rx / dist * pen; mp.y += ry / dist * pen;
                    applyFriction(mp, f);
                    if (mp.hasWheel) rollWheel(mp, -nX, -nY);
                }
            } else {
                double dist = rx * nX + ry * nY, pen = dist + r;
                if (pen > 0) {
                    pen = -pen;
                    mp.x += nX * pen; mp.y += nY * pen;
                    applyFriction(mp, f);
                    if (onHit) onHit(int(i), pen);
                    if (mp.hasWheel) rollWheel(mp, -nX, -nY);
                }
            }
        }
        if (mp.x < t.segs.front().x0 + mp.r) { // left wall
            mp.x = t.segs.front().x0 + mp.r;
            applyFriction(mp, f);
            if (mp.hasWheel) rollWheel(mp, 1, 0);
        }
    }
}

void SoftCar::spin(double add, double maxSpeed) {
    for (auto& mp : p)
        if (mp.hasWheel) mp.wheel.s = clampd(mp.wheel.s + add, -maxSpeed, maxSpeed);
}

void SoftCar::lean(int dir, double riderPower) {
    MassPoint &a = p[rear], &b = p[front];
    double dx = b.x - a.x, dy = b.y - a.y;
    double d = std::sqrt(dx * dx + dy * dy) / 2;
    double ang = (std::atan2(dy, dx) * 180 / kPi + dir * riderPower) * kPi / 180;
    double mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    a.x = mx - std::cos(ang) * d; a.y = my - std::sin(ang) * d;
    b.x = mx + std::cos(ang) * d; b.y = my + std::sin(ang) * d;
}

void SoftCar::push(double dx, int from, int to) {
    for (int i = from; i < to && i < int(p.size()); i++) p[i].x += dx;
}

void SoftCar::wreck(double grav) {
    for (int i : def->breakOnCrash)
        if (i >= 0 && i < int(springs.size())) springs[i].alive = false;
    for (auto& mp : p) {
        if (!mp.hasWheel) { mp.collide = true; mp.g = grav; }
    }
}

double SoftCar::angleAt(const AngleCheck& a) const {
    const MassPoint &v = p[a.vertex], &p0 = p[a.a], &p1 = p[a.b];
    double a0 = std::atan2(p0.y - v.y, p0.x - v.x) * 180 / kPi;
    double a1 = std::atan2(p1.y - v.y, p1.x - v.x) * 180 / kPi;
    return a1 - a0;
}

double SoftCar::bodyAngle() const {
    const auto& bp = def->bodyPoints;
    const MassPoint &a = p[bp[0]], &b = p[bp[1]];
    return std::atan2(b.y - a.y, b.x - a.x) * 180 / kPi;
}

void SoftCar::bodyCenter(double& x, double& y) const {
    x = y = 0;
    for (int i : def->bodyPoints) { x += p[i].x; y += p[i].y; }
    x /= def->bodyPoints.size(); y /= def->bodyPoints.size();
}

void SoftCar::trackCenter(double& x, double& y) const {
    // carX/carY: mean of both wheels and the two upper body points
    x = (p[0].x + p[1].x + p[4].x + p[5].x) / 4;
    y = (p[0].y + p[1].y + p[4].y + p[5].y) / 4;
}
