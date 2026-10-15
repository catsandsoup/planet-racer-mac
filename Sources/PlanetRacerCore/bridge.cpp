#include "PlanetRacerCore.h"
#include "data.hpp"
#include "race.hpp"
#include "career.hpp"
#include <algorithm>
#include <cmath>
#include <deque>

struct PRGame {
    GameData data;
    std::string error;
    Race race;
    bool raceActive = false;
    std::deque<SfxEvent> sfx;
    Career career;
    std::string careerError, careerJson;
};

static uint32_t pack(const Rgb& c) { return (uint32_t(c.r) << 16) | (uint32_t(c.g) << 8) | c.b; }
static int clampi(int v, int lo, int hi) { return std::max(lo, std::min(hi, v)); }

extern "C" {

PRGame* pr_create(const char* dataDir) {
    PRGame* g = new PRGame();
    if (!g->data.load(dataDir ? dataDir : "data", g->error) && g->error.empty()) g->error = "could not load game data";
    g->career.bind(g->data);
    return g;
}
void pr_destroy(PRGame* g) { delete g; }
const char* pr_error(const PRGame* g) { return g->error.c_str(); }

int pr_planet_count(const PRGame* g) { return int(g->data.planets.size()); }
PRPlanetInfo pr_planet(const PRGame* g, int i) {
    const Planet& p = g->data.planets[clampi(i, 0, pr_planet_count(g) - 1)];
    return {p.id, p.name.c_str(), p.description.c_str(), p.image.c_str(), p.buildings.c_str(),
            p.surface, p.gravity, p.size, p.difficulty, pack(p.fill), pack(p.line)};
}
int pr_opponent_count(const PRGame* g) { return int(g->data.opponents.size()); }
PROpponentInfo pr_opponent(const PRGame* g, int i) {
    const Opponent& o = g->data.opponents[clampi(i, 0, pr_opponent_count(g) - 1)];
    return {o.name.c_str(), o.homePlanet, o.rep, o.chassis, o.wheels, o.engine, o.afterburner, o.color, o.face, o.faceFrame};
}
int pr_part_count(const PRGame* g, int kind) {
    const Parts& P = g->data.parts;
    switch (kind) {
    case PR_ENGINE: return int(P.engines.size());
    case PR_TIRES: return int(P.tires.size());
    case PR_CHASSIS: return int(P.chassis.size());
    default: return int(P.afterburners.size());
    }
}
PRPartInfo pr_part(const PRGame* g, int kind, int i) {
    const Parts& P = g->data.parts;
    i = clampi(i, 0, pr_part_count(g, kind) - 1);
    switch (kind) {
    case PR_ENGINE: { auto& e = P.engines[i]; return {e.name.c_str(), e.speed, e.price, e.sound, 0}; }
    case PR_TIRES: { auto& e = P.tires[i]; return {e.name.c_str(), e.grip, e.price, e.art, 0}; }
    case PR_CHASSIS: { auto& e = P.chassis[i]; return {e.name.c_str(), e.speed, e.price, e.art, std::max(1, int(e.wheelTints.size()))}; }
    default: { auto& e = P.afterburners[i]; return {e.name.c_str(), e.seconds, e.price, i + 1, 0}; }
    }
}
uint32_t pr_wheel_tint(const PRGame* g, int chassis, int color) {
    const ChassisPart& c = g->data.parts.chassis[clampi(chassis, 0, pr_part_count(g, PR_CHASSIS) - 1)];
    if (color >= 1 && color <= int(c.wheelTints.size())) return pack(c.wheelTints[color - 1]);
    return 0x00FF11; // the original's fallback (65297)
}
double pr_top_speed(const PRGame* g, int engine, int chassis) {
    PRPartInfo e = pr_part(g, PR_ENGINE, engine), c = pr_part(g, PR_CHASSIS, chassis);
    return std::min(1.4 * e.value * c.value, Race::kMaxSpeed) / Race::kMaxSpeed;
}

void pr_race_begin(PRGame* g, PRRaceConfig c) {
    const Parts& P = g->data.parts;
    RaceSetup s;
    s.planet = &g->data.planets[clampi(c.planet, 0, pr_planet_count(g) - 1)];
    const Opponent& op = g->data.opponents[clampi(c.opponent, 0, pr_opponent_count(g) - 1)];
    s.opponent = &op;
    s.engine = clampi(c.engine, 0, int(P.engines.size()) - 1);
    s.tires = clampi(c.tires, 0, int(P.tires.size()) - 1);
    s.chassis = clampi(c.chassis, 0, int(P.chassis.size()) - 1);
    s.afterburner = clampi(c.afterburner, 0, int(P.afterburners.size()) - 1);
    s.color = clampi(c.color, 1, std::max(1, int(P.chassis[s.chassis].wheelTints.size())));
    s.difficulty = clampi(c.difficulty, 0, 2);
    s.oppChassis = clampi(op.chassis - 1, 0, int(P.chassis.size()) - 1);
    s.oppTires = clampi(op.wheels - 1, 0, int(P.tires.size()) - 1);
    s.oppColor = clampi(op.color, 1, std::max(1, int(P.chassis[s.oppChassis].wheelTints.size())));
    s.kingOpponent = s.planet->id == 5; // the Moon is always a race against the King
    s.betLabel = s.kingOpponent ? "VS THE KING" : "QUICK RACE";
    g->race.begin(g->data, s);
    g->raceActive = true;
    g->sfx.clear();
}

void pr_race_set_view(PRGame* g, double w, double h) { g->race.viewW = w; g->race.viewH = h; }
void pr_race_start(PRGame* g) {
    g->race.start();
    for (auto& e : g->race.events) g->sfx.push_back(e);
    g->race.events.clear();
}
void pr_race_tick(PRGame* g, PRInput in) {
    if (!g->raceActive) return;
    g->race.tick({in.up, in.down, in.left, in.right, in.boost});
    for (auto& e : g->race.events) g->sfx.push_back(e);
    g->race.events.clear();
}
void pr_race_abandon(PRGame* g) {
    if (g->race.started && !g->race.finished) g->race.abandon();
    for (auto& e : g->race.events) g->sfx.push_back(e);
    g->race.events.clear();
}

static void copyPoints(const SoftCar& c, PRPoint* out, int& n) {
    n = std::min(int(c.p.size()), PR_MAX_POINTS);
    for (int i = 0; i < n; i++) {
        const MassPoint& m = c.p[i];
        out[i] = {m.x, m.y, m.r, m.wheel.x, m.wheel.y, m.hasWheel};
    }
}

void pr_race_frame(const PRGame* g, PRFrame* o) {
    const Race& r = g->race;
    *o = PRFrame{};
    if (!g->raceActive) return;
    const Parts& P = g->data.parts;
    int n = 0;
    copyPoints(r.car, o->car, n);
    copyPoints(r.opp, o->opp, o->pointCount);
    o->pointCount = std::min(n, o->pointCount);
    const CarDef& d = g->data.car;
    o->bodyA = d.bodyPoints.size() > 0 ? d.bodyPoints[0] : 2;
    o->bodyB = d.bodyPoints.size() > 1 ? d.bodyPoints[1] : 3;
    o->bodyCount = std::min(4, int(d.bodyPoints.size()));
    for (int i = 0; i < o->bodyCount; i++) o->bodyIdx[i] = d.bodyPoints[i];
    o->camX = r.camX; o->camY = r.camY;
    o->started = r.started; o->crashed = r.crashed; o->finished = r.finished;
    o->oppVisible = r.oppVisible; o->oppBurning = r.oppBurning; o->boosting = r.boosting; o->engineOn = r.engineOn;
    switch (r.result()) {
    case RaceResult::Won: o->result = PR_WON; break;
    case RaceResult::Lost: o->result = PR_LOST; break;
    case RaceResult::Crashed: o->result = PR_CRASHED; break;
    default: o->result = PR_RUNNING;
    }
    o->boostFraction = r.boostTotal ? double(r.boostLeft) / r.boostTotal : 0;
    o->damageFlash = r.damageFlash; o->damage = std::min(r.damage, 100.0); o->raceTime = r.raceTime;
    const Planet& pl = *r.setup.planet;
    double bx, by;
    r.car.bodyCenter(bx, by);
    o->playerProgress = std::clamp(bx / pl.size, 0.0, 1.0);
    o->oppProgress = std::clamp(r.oppXPos / pl.size, 0.0, 1.0);
    o->musicFade = r.musicFade;
    o->engineSound = r.engineSound;
    o->planetSize = pl.size;
    o->finishGroundY = r.terrain.groundY(pl.size);
    o->showStartBuildings = r.startBuildings;
    const RaceSetup& s = r.setup;
    o->chassisArt = P.chassis[s.chassis].art; o->color = s.color; o->tireArt = P.tires[s.tires].art;
    o->oppKingmobile = s.kingOpponent;
    o->playerKingmobile = s.playerKing;
    if (s.playerKing) {
        o->chassisArt = 3;
        o->tireArt = P.tires[std::min<size_t>(2, P.tires.size() - 1)].art;
    }
    o->oppChassisArt = s.kingOpponent ? 3 : P.chassis[s.oppChassis].art;
    o->oppColor = s.oppColor; o->oppTireArt = P.tires[s.oppTires].art;
    o->wheelTint = s.playerKing ? 0xFFFF00 : pr_wheel_tint(g, s.chassis, s.color);
    o->oppWheelTint = s.kingOpponent ? 0xFFFF00 : pr_wheel_tint(g, s.oppChassis, s.oppColor);
}

int pr_race_segments(const PRGame* g, PRSegment* out, int max) {
    int n = 0;
    for (const Segment& s : g->race.terrain.segs) {
        if (n >= max) break;
        out[n++] = {s.x0, s.y0, s.x1, s.y1};
    }
    return n;
}
int pr_race_stars(const PRGame* g, PRStar* out, int max) {
    int n = 0;
    for (const Star& s : g->race.stars) { if (n >= max) break; out[n++] = {s.x, s.y, s.frame, s.distance}; }
    return n;
}
int pr_race_tiles(const PRGame* g, PRTile* out, int max) {
    int n = 0;
    for (const SurfaceTile& t : g->race.tiles) { if (n >= max) break; out[n++] = {t.x, t.y, t.frame}; }
    return n;
}
bool pr_race_poll_sfx(PRGame* g, int* id, float* volume) {
    if (g->sfx.empty()) return false;
    SfxEvent e = g->sfx.front();
    g->sfx.pop_front();
    *id = int(e.id); *volume = e.volume;
    return true;
}
double pr_ground_y(const PRGame* g, double x) { return g->race.terrain.groundY(x); }
double pr_ground_slope(const PRGame* g, double x) {
    for (const Segment& s : g->race.terrain.segs)
        if (x >= s.x0 && x <= s.x1) return std::atan2(s.y1 - s.y0, s.x1 - s.x0) * 180 / 3.141592653589793;
    return 0;
}
const char* pr_race_opponent_name(const PRGame* g) { return g->race.setup.opponent ? g->race.setup.opponent->name.c_str() : ""; }
const char* pr_race_planet_name(const PRGame* g) { return g->race.setup.planet ? g->race.setup.planet->name.c_str() : ""; }
int pr_race_planet_index(const PRGame* g) {
    const Planet* p = g->race.setup.planet;
    return p ? int(p - g->data.planets.data()) : 0;
}
double pr_tick_seconds(void) { return Race::kTick; }
const char* pr_race_bet_label(const PRGame* g) { return g->race.setup.betLabel.c_str(); }

// ---- career --------------------------------------------------------------------------

static int kindOf(int k) { return clampi(k, 0, kKinds - 1); }
static int code(ActionResult r) {
    switch (r) {
    case ActionResult::Ok: return PR_OK;
    case ActionResult::NotEnoughCash: return PR_NOT_ENOUGH_CASH;
    case ActionResult::NeedCertificate: return PR_NEED_CERTIFICATE;
    default: return PR_NOTHING;
    }
}

void pr_career_new(PRGame* g, const char* name, int difficulty) { g->career.newGame(name ? name : "", difficulty); }
bool pr_career_load_json(PRGame* g, const char* json) {
    g->careerError.clear();
    return g->career.fromJson(json ? json : "", g->careerError);
}
const char* pr_career_error(const PRGame* g) { return g->careerError.c_str(); }
const char* pr_career_to_json(PRGame* g) { g->careerJson = g->career.toJson(); return g->careerJson.c_str(); }
bool pr_career_start_garage(PRGame* g) { return g->career.startGarage(); }

PRCareerInfo pr_career_info(const PRGame* g) {
    const Career& c = g->career;
    const CareerState& s = c.s;
    int king = -1;
    if (!s.youTheKing)
        for (size_t i = 0; i < g->data.opponents.size(); i++)
            if (g->data.opponents[i].homePlanet == s.kingPlanet && g->data.opponents[i].key == s.kingKey) king = int(i);
    return {s.name.c_str(), s.difficulty, s.cash, s.rep, s.time, s.certificate, s.youTheKing, s.noTravelMessage,
            c.planet, c.planetTime, 20, king};
}

int pr_career_part_count(const PRGame* g, int kind) { return g->career.count(kindOf(kind)); }
int pr_career_current(const PRGame* g, int kind) { return g->career.s.current[kindOf(kind)]; }
PROwnedPart pr_career_part(const PRGame* g, int kind, int index) {
    const auto& v = g->career.s.parts[kindOf(kind)];
    if (index < 0 || index >= int(v.size())) return {0, 0, 1};
    return {v[index].type, v[index].wear, v[index].color};
}
void pr_career_select(PRGame* g, int kind, int delta) { g->career.select(kindOf(kind), delta); }
int pr_career_repair_price(const PRGame* g, int kind) { return g->career.repairPrice(kindOf(kind)); }
int pr_career_repair(PRGame* g, int kind) { return code(g->career.repair(kindOf(kind))); }
bool pr_career_can_race(const PRGame* g) { return g->career.canRace(); }
double pr_career_speed_stat(const PRGame* g) { return g->career.speedStat(); }
double pr_career_grip_stat(const PRGame* g) { return g->career.gripStat(); }

int pr_career_stock(const PRGame* g, int kind, int type) {
    const auto& v = g->career.s.stock[kindOf(kind)];
    return type >= 0 && type < int(v.size()) ? v[type] : 0;
}
int pr_career_buy(PRGame* g, int kind, int type, int color) { return code(g->career.buy(kindOf(kind), type, color)); }
int pr_career_sell_value(const PRGame* g, int kind, int index) { return g->career.sellValue(kindOf(kind), index); }
void pr_career_sell(PRGame* g, int kind, int index) { g->career.sell(kindOf(kind), index); }

int pr_career_travel_cost(const PRGame* g, int planetId) { return g->career.travelCost(planetId); }
int pr_career_opponents_on(const PRGame* g, int planetId) { return g->career.opponentsOn(planetId); }
int pr_career_travel(PRGame* g, int planetId) { return code(g->career.travel(planetId)); }
void pr_career_set_no_travel_message(PRGame* g, bool on) { g->career.s.noTravelMessage = on; }

PREncounter pr_career_encounter(const PRGame* g) {
    const Career& c = g->career;
    int st;
    switch (c.encounter) {
    case Encounter::WaitKing: st = PR_ENC_WAIT_KING; break;
    case Encounter::VehicleUpdate: st = PR_ENC_VEHICLE_UPDATE; break;
    case Encounter::Offer: st = PR_ENC_OFFER; break;
    case Encounter::Accepted: st = PR_ENC_ACCEPTED; break;
    case Encounter::Declined: st = PR_ENC_DECLINED; break;
    case Encounter::Refused: st = PR_ENC_REFUSED; break;
    case Encounter::NoCash: st = PR_ENC_NO_CASH; break;
    default: st = PR_ENC_NONE;
    }
    if (c.planet == 0) st = PR_ENC_NONE;
    return {st, c.planet ? c.opponentIndex() : 0, c.sentence.c_str(), c.currentAmount, c.initialAmount,
            c.negotiating, c.kingGame, c.oppKing, c.youKing, c.planet ? c.opponentColor() : 1};
}
void pr_career_adjust_amount(PRGame* g, int dir) { g->career.adjustAmount(dir); }
void pr_career_offer_car(PRGame* g) { g->career.offerCar(); }
bool pr_career_accept(PRGame* g) { return g->career.accept(); }
void pr_career_decline(PRGame* g) { g->career.decline(); }
void pr_career_continue(PRGame* g) { g->career.advanceEncounter(); }
void pr_career_refusal_elapsed(PRGame* g) { g->career.tickRefusal(); }
bool pr_career_go_home(PRGame* g) { bool toTitle = false; g->career.goHomeButton(toTitle); return toTitle; }
int pr_career_take_trouble(PRGame* g) {
    Trouble t = g->career.trouble;
    g->career.trouble = Trouble::None;
    switch (t) {
    case Trouble::CarLost: return PR_TROUBLE_CAR_LOST;
    case Trouble::Time: return PR_TROUBLE_TIME;
    case Trouble::Damage: return PR_TROUBLE_DAMAGE;
    default: return PR_TROUBLE_NONE;
    }
}
bool pr_career_take_certificate(PRGame* g) { bool a = g->career.awardCertificate; g->career.awardCertificate = false; return a; }

void pr_career_race_begin(PRGame* g) {
    RaceSetup s = g->career.raceSetup();
    g->race.begin(g->data, s);
    g->raceActive = true;
    g->sfx.clear();
}
void pr_career_race_settle(PRGame* g) { g->career.settle(g->race); }
const char* pr_career_result_head(const PRGame* g) { return g->career.resultHead.c_str(); }
const char* pr_career_result_line(const PRGame* g) { return g->career.resultLine.c_str(); }

} // extern "C"
