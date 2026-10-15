#include "career.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cmath>

using nlohmann::json;

static int roundAS(double v) { return int(std::floor(v + 0.5)); } // Math.round
static double loss(double wear) { return (100 - wear / 2) / 100; }

// ---- new game / garage --------------------------------------------------------------

void Career::newGame(const std::string& name, int difficulty) {
    s = CareerState();
    planet = 0;
    encounter = Encounter::None;
    trouble = Trouble::None;
    awardCertificate = false;
    s.name = name;
    s.difficulty = std::clamp(difficulty, 0, 2);
    s.diffFactor = 1 + (s.difficulty - 1) / 5.0;
    s.cash = roundAS(10000 * ((1 - s.diffFactor) * 2 + 1)); // 14000 / 10000 / 6000
    s.rep = 15;
    for (int k = 0; k < kKinds; k++) { s.parts[k] = {OwnedPart{0, 0, 1}}; s.current[k] = 0; }
    s.oppColors.clear();
    for (auto& o : data->opponents) s.oppColors.push_back(o.color);
    s.kingPlanet = 3; s.kingKey = 0;
    refillShop();
    newPlanetData();
}

bool Career::startGarage() {
    planet = 0;
    encounter = Encounter::None;
    if (s.youTheKing) { // the King lives on the Moon, waiting for challengers
        planet = 5;
        nrOfOpponents = 1;
        planetTime = 0;
        afterRace = false;
        enterPlanet();
        return planet != 0;
    }
    return false;
}

const OwnedPart* Career::currentPart(int kind) const {
    const auto& v = s.parts[kind];
    if (v.empty()) return nullptr;
    return &v[std::clamp(s.current[kind], 0, int(v.size()) - 1)];
}

void Career::select(int kind, int delta) {
    int n = count(kind);
    s.current[kind] = n == 0 ? 0 : std::clamp(s.current[kind] + delta, 0, n - 1);
}

int Career::partPrice(int kind, int type) const {
    const Parts& P = data->parts;
    switch (kind) {
    case kEngine: return type < int(P.engines.size()) ? P.engines[type].price : 0;
    case kTires: return type < int(P.tires.size()) ? P.tires[type].price : 0;
    case kChassis: return type < int(P.chassis.size()) ? P.chassis[type].price : 0;
    default: return type < int(P.afterburners.size()) ? P.afterburners[type].price : 0;
    }
}

std::string Career::partName(int kind, int type) const {
    const Parts& P = data->parts;
    switch (kind) {
    case kEngine: return type < int(P.engines.size()) ? P.engines[type].name : "";
    case kTires: return type < int(P.tires.size()) ? P.tires[type].name : "";
    case kChassis: return type < int(P.chassis.size()) ? P.chassis[type].name : "";
    default: return type < int(P.afterburners.size()) ? P.afterburners[type].name : "";
    }
}

int Career::colorCount(int chassisType) const {
    const auto& c = data->parts.chassis;
    if (chassisType < 0 || chassisType >= int(c.size())) return 1;
    return std::max(1, int(c[chassisType].wheelTints.size()));
}

int Career::repairPrice(int kind) const {
    const OwnedPart* p = currentPart(kind);
    if (!p) return 0;
    return roundAS(partPrice(kind, p->type) * p->wear / 100 * 0.4); // clickOkRepair
}

ActionResult Career::repair(int kind) {
    const OwnedPart* p = currentPart(kind);
    if (!p || p->wear <= 0) return ActionResult::Nothing;
    int price = repairPrice(kind);
    if (s.cash < price) return ActionResult::NotEnoughCash;
    s.parts[kind][s.current[kind]].wear = 0;
    s.cash -= price;
    return ActionResult::Ok;
}

bool Career::allPartsPresent() const {
    for (int k = 0; k < kKinds; k++) if (s.parts[k].empty()) return false;
    return true;
}

bool Career::noBadDamage() const {
    for (int k : {kEngine, kTires, kChassis}) {
        const OwnedPart* p = currentPart(k);
        if (p && p->wear >= 100) return false;
    }
    return true;
}

double Career::speedStat() const {
    const OwnedPart *e = currentPart(kEngine), *c = currentPart(kChassis);
    if (!e || !c) return 0;
    const Parts& P = data->parts;
    // initCarStats: the bar is 31 * chassis * engine pixels (each weakened by wear) of a ~100 px slot
    double w = 31 * (P.chassis[c->type].speed * loss(c->wear)) * (P.engines[e->type].speed * loss(e->wear));
    return std::clamp(w / 100, 0.0, 1.0);
}

double Career::gripStat() const {
    const OwnedPart* t = currentPart(kTires);
    if (!t) return 0;
    double w = (0.05 - data->parts.tires[t->type].grip) / 0.05 * 99 * loss(t->wear);
    return std::clamp(w / 100, 0.0, 1.0);
}

// ---- shop ----------------------------------------------------------------------------

void Career::refillShop() { // beginShopItems
    const Parts& P = data->parts;
    const int n[kKinds] = {int(P.engines.size()), int(P.tires.size()), int(P.chassis.size()), int(P.afterburners.size())};
    const int base[kKinds] = {6, 8, 4, 6};
    for (int k = 0; k < kKinds; k++) {
        s.stock[k].assign(n[k], 0);
        for (int i = 0; i < n[k]; i++) s.stock[k][i] = rng.below(base[k] - i);
        if (n[k] > 0 && s.stock[k][0] == 0) s.stock[k][0] = 1;
    }
}

ActionResult Career::buy(int kind, int type, int color) {
    if (type < 0 || type >= int(s.stock[kind].size()) || s.stock[kind][type] <= 0) return ActionResult::Nothing;
    int price = partPrice(kind, type);
    if (s.cash < price) return ActionResult::NotEnoughCash;
    s.stock[kind][type]--;
    s.cash -= price;
    s.parts[kind].push_back({type, 0, kind == kChassis ? std::clamp(color, 1, colorCount(type)) : 1});
    return ActionResult::Ok;
}

int Career::sellValue(int kind, int index) const {
    if (index < 0 || index >= count(kind)) return 0;
    const OwnedPart& p = s.parts[kind][index];
    int wear = roundAS(p.wear);
    return roundAS(partPrice(kind, p.type) * ((100 - wear) / 100.0 / 2));
}

void Career::sell(int kind, int index) {
    if (index < 0 || index >= count(kind)) return;
    s.cash += sellValue(kind, index);
    s.parts[kind].erase(s.parts[kind].begin() + index);
    s.current[kind] = 0;
}

// ---- travel --------------------------------------------------------------------------

int Career::planetIndex(int id) const {
    for (size_t i = 0; i < data->planets.size(); i++) if (data->planets[i].id == id) return int(i);
    return -1;
}

int Career::travelCost(int id) const {
    int i = planetIndex(id);
    return i < 0 ? 0 : data->planets[i].travelCost;
}

void Career::newPlanetData() {
    s.planetOpponents[1] = 2 + rng.below(6);
    s.planetOpponents[2] = 2 + rng.below(6);
    s.planetOpponents[3] = 4 + rng.below(4);
    s.planetOpponents[4] = 3 + rng.below(5);
    s.planetOpponents[5] = 1;
}

ActionResult Career::travel(int id) {
    if (planetIndex(id) < 0 || id < 1 || id > 5) return ActionResult::Nothing;
    if ((id == 1 || id == 2) && !s.certificate) return ActionResult::NeedCertificate;
    int cost = travelCost(id);
    if (s.cash < cost) return ActionResult::NotEnoughCash;
    s.cash -= cost;
    planet = id;
    nrOfOpponents = opponentsOn(id);
    planetTime = 0; // the "startgame" frame
    afterRace = false;
    enterPlanet();
    return ActionResult::Ok;
}

// ---- rivals --------------------------------------------------------------------------

int Career::dataOpponent(int planetId, int key) const {
    for (size_t i = 0; i < data->opponents.size(); i++)
        if (data->opponents[i].homePlanet == planetId && data->opponents[i].key == key) return int(i);
    return -1;
}

void Career::initOpponents(int p) {
    auto home = [this](int q) {
        std::vector<int> v;
        for (size_t i = 0; i < data->opponents.size(); i++) if (data->opponents[i].homePlanet == q) v.push_back(int(i));
        return v;
    };
    auto pick = [&](int q) { auto v = home(q); return v.empty() ? -1 : v[rng.below(int(v.size()))]; };
    opponents.clear();
    int visitors[3] = {0, 0, 0};
    switch (p) {
    case 1: visitors[0] = 2; visitors[1] = 3; visitors[2] = 4; break;
    case 2: visitors[0] = 1; visitors[1] = 3; visitors[2] = 4; break;
    case 3: visitors[0] = 2; visitors[1] = 1; visitors[2] = 4; break;
    case 4: visitors[0] = 2; visitors[1] = 3; visitors[2] = 1; break;
    }
    if (p >= 1 && p <= 4) {
        opponents = home(p);
        for (int q : visitors) { int o = pick(q); if (o >= 0) opponents.push_back(o); }
    } else if (p == 5) {
        if (oppKing) { int k = dataOpponent(s.kingPlanet, s.kingKey); if (k >= 0) opponents.push_back(k); }
        else opponents = home(1);
    }
    if (p == s.kingPlanet) { // the King doesn't race on his home planet (the original's loop skips the next entry)
        for (size_t i = 0; i < opponents.size(); i++)
            if (data->opponents[opponents[i]].key == s.kingKey) opponents.erase(opponents.begin() + i);
    }
    if (opponents.empty()) opponents = home(1);
    tempers.clear();
    for (int o : opponents) tempers.push_back(data->opponents[o].temper);
}

void Career::initSession() { // the career half of init()
    planetTime++;
    oppKing = kingGame && !s.youTheKing;
    youKing = s.youTheKing && kingGame;
    carLost = false;
}

void Career::enterPlanet() { // startOppSelect
    kingGame = planet == 5 || s.youTheKing;
    initSession();
    if (!afterRace) {
        initOpponents(planet);
        // aRandomOpponents.randoMix(n): a shuffled 0..n-1, then cut to the planet's rival count
        int rdm = int(opponents.size());
        order.clear();
        for (int c = 0; c < rdm; c++) order.push_back(c);
        for (int i = 0, r = rdm; i < rdm; i++, r--) {
            int at = rng.below(r);
            int v = order[at];
            order.push_back(v);
            order.erase(order.begin() + at);
        }
        if (nrOfOpponents < int(order.size())) order.resize(std::max(1, nrOfOpponents));
        orderIndex = 0;
        currentOpponent = order[0];
        if (kingGame) currentOpponent = oppKing ? 0 : rng.below(int(opponents.size()));
    }
    arrive();
}

void Career::nextInOrder() {
    if (order.empty()) return;
    orderIndex = orderIndex < int(order.size()) - 1 ? orderIndex + 1 : 0;
    currentOpponent = order[orderIndex];
}

int Career::opponentIndex() const {
    if (opponents.empty()) return 0;
    return opponents[std::clamp(currentOpponent, 0, int(opponents.size()) - 1)];
}

int Career::opponentColor() const {
    int i = opponentIndex();
    return i < int(s.oppColors.size()) ? s.oppColors[i] : 1;
}

void Career::computeSpeeds() { // setupVehicle(), opponent-select branch
    const Opponent& o = data->opponents[opponentIndex()];
    double k = (o.rep - 50) / 200.0 + 1;
    aiSpeed = 1.4 * k * k;
    const OwnedPart *e = currentPart(kEngine), *c = currentPart(kChassis);
    playerSpeed = 1.4 * (e ? data->parts.engines[e->type].speed : 1) * (c ? data->parts.chassis[c->type].speed : 1);
}

void Career::arrive() { // moveOppSelect, oSstap == null
    computeSpeeds();
    Trouble t = checkForTrouble(false);
    if (t != Trouble::None) { quitToGarage(t); return; }
    if (youKing) encounter = Encounter::WaitKing;
    else if (afterRace) { afterRace = false; encounter = Encounter::VehicleUpdate; }
    else openOffer();
}

std::string Career::sentenceFor(const char* kind) {
    auto it = data->lines.find(kind);
    if (it == data->lines.end() || it->second.empty()) return "...";
    return it->second[rng.below(int(it->second.size()))];
}

int Career::setAmount() { // manageAmount("setamount")
    const Opponent& o = data->opponents[opponentIndex()];
    double base = o.rep * 140 * (1 - s.diffFactor + 1) + travelCost(planet) * 3;
    double ratio = o.rep * aiSpeed / (s.rep * playerSpeed);
    double a = ratio * base;
    a *= 1.4 - rng.unit();
    a = a >= 10000 ? roundAS(a / 1000) * 1000.0 : roundAS(a / 100) * 100.0;
    int amount = std::max(50, int(a));
    if (ratio > 0.8 && rng.unit() > 0.9) amount = 2;           // the car
    if (ratio < 0.2 + rng.unit() / 6) amount = 3;              // chicken
    if (ratio > 3.5 + rng.unit() && rng.unit() > 0.3) amount = 0; // you're beneath them
    if (opponentTemper() > 4 + rng.below(4)) amount = 1;       // temper
    if (kingGame) amount = 4;                                  // the crown
    return amount;
}

void Career::openOffer() { // attachOpponentPanel
    negotiating = false;
    initialAmount = setAmount();
    currentAmount = initialAmount;
    switch (initialAmount) {
    case 4: sentence = sentenceFor(oppKing ? "king" : "youking"); encounter = Encounter::Offer; break;
    case 0: sentence = sentenceFor("decline"); encounter = Encounter::Refused; break;
    case 1: sentence = sentenceFor("temper"); encounter = Encounter::Refused; break;
    case 3: sentence = sentenceFor("chicken"); encounter = Encounter::Refused; break;
    case 2: sentence = sentenceFor("car"); encounter = Encounter::Offer; break;
    default:
        sentence = sentenceFor(rng.unit() < 0.97 ? "sentence" : "weird");
        afw = -1;
        encounter = Encounter::Offer;
    }
}

void Career::adjustAmount(int dir) { // manageAmount("up"/"down")
    if (encounter != Encounter::Offer || initialAmount <= 4) return;
    int& a = currentAmount;
    if (a == 2) a = initialAmount;
    else if (dir > 0) a += a >= 10000 ? 1000 : a >= 1000 ? 100 : a >= 100 ? 50 : 10;
    else a -= a > 10000 ? 1000 : a > 1000 ? 100 : a > 100 ? 50 : 10;
    if (a != 2 && a < 50) a = 50;
    negotiating = a != initialAmount;
}

void Career::offerCar() {
    if (encounter != Encounter::Offer || initialAmount <= 4) return;
    currentAmount = 2;
    negotiating = true;
}

bool Career::negotiate(int amount) {
    bool ok = false;
    const Opponent& o = data->opponents[opponentIndex()];
    if (amount == 2) {
        double r = o.rep * aiSpeed / s.rep * playerSpeed; // sic: the original's precedence
        if (r > 0.95 && rng.unit() < 0.3 * r) ok = true;
        if (rng.unit() > 0.2) ok = false;
    } else {
        if (afw < 0) afw = amount * (rng.unit() * 0.7);
        if (amount > initialAmount - afw && amount < initialAmount + afw) ok = true;
        if (rng.unit() > 0.7) ok = false;
    }
    return ok;
}

bool Career::accept() {
    const std::string name = data->opponents[opponentIndex()].name;
    switch (encounter) {
    case Encounter::Offer:
        if (negotiating) {
            bool car = currentAmount == 2;
            if (negotiate(currentAmount)) {
                encounter = Encounter::Accepted;
                sentence = car ? name + " has accepted your offer to race for the cars."
                               : name + " has accepted your offer of $ " + std::to_string(currentAmount) + ".";
            } else {
                tempers[currentOpponent]++;
                encounter = Encounter::Declined;
                sentence = car ? name + " has declined your offer to race for the cars."
                               : name + " has declined your offer of $ " + std::to_string(currentAmount) + ".";
            }
            return false;
        }
        if (s.cash >= currentAmount) return true;
        encounter = Encounter::NoCash;
        sentence = "You do not have enough money to accept this amount.";
        return false;
    case Encounter::Accepted: return true;
    default: advanceEncounter(); return false;
    }
}

void Career::decline() {
    switch (encounter) {
    case Encounter::Offer:
        if (kingGame) return; // no DECLINE in the King game
        tempers[currentOpponent] += 2;
        leave();
        break;
    case Encounter::Accepted: break;
    default: advanceEncounter();
    }
}

void Career::advanceEncounter() {
    switch (encounter) {
    case Encounter::WaitKing:
    case Encounter::VehicleUpdate: openOffer(); break;
    case Encounter::NoCash: tempers[currentOpponent] += 2; leave(); break;
    case Encounter::Declined:
    case Encounter::Refused: leave(); break;
    default: break;
    }
}

void Career::tickRefusal() { if (encounter == Encounter::Refused) leave(); }

void Career::leave() { // the rival drives off; the next one pulls up
    if (!kingGame) nextInOrder();
    initSession();
    arrive();
}

void Career::goHomeButton(bool& toTitle) { // mcGoHome
    toTitle = kingGame;
    if (kingGame) { planet = 0; encounter = Encounter::None; afterRace = false; }
    else quitToGarage(Trouble::None);
}

void Career::quitToGarage(Trouble t) {
    // quitToGarage -> the "startmenu" frame: a trip home, fresh shop stock and rival counts
    planet = 0;
    encounter = Encounter::None;
    afterRace = false;
    s.time++;
    refillShop();
    newPlanetData();
    trouble = t;
}

Trouble Career::checkForTrouble(bool crashed) const {
    if (carLost) return Trouble::CarLost;
    if (planetTime >= 20) return Trouble::Time;
    for (int k : {kEngine, kChassis, kTires}) {
        const OwnedPart* p = currentPart(k);
        if (p && p->wear >= 100) return Trouble::Damage;
    }
    if (crashed) return Trouble::Damage;
    return Trouble::None;
}

// ---- races ---------------------------------------------------------------------------

std::string Career::betLabel() const {
    if (currentAmount == 2) return "CAR";
    if (currentAmount == 4) return "CROWN";
    return "$ " + std::to_string(currentAmount);
}

RaceSetup Career::raceSetup() {
    initSession(); // start() -> init(): counts toward the time limit
    RaceSetup r;
    r.planet = &data->planets[std::max(0, planetIndex(planet))];
    const Opponent& o = data->opponents[opponentIndex()];
    r.opponent = &o;
    auto type = [this](int k) { const OwnedPart* p = currentPart(k); return p ? p->type : 0; };
    auto wear = [this](int k) { const OwnedPart* p = currentPart(k); return p ? p->wear : 0.0; };
    r.engine = type(kEngine); r.tires = type(kTires); r.chassis = type(kChassis); r.afterburner = type(kAfterburner);
    const OwnedPart* ch = currentPart(kChassis);
    r.color = ch ? ch->color : 1;
    r.engineWear = wear(kEngine); r.chassisWear = wear(kChassis); r.tireWear = wear(kTires); r.afterburnerWear = wear(kAfterburner);
    const Parts& P = data->parts;
    r.oppChassis = std::clamp(o.chassis - 1, 0, int(P.chassis.size()) - 1);
    r.oppTires = std::clamp(o.wheels - 1, 0, int(P.tires.size()) - 1);
    r.oppColor = opponentColor();
    r.difficulty = s.difficulty;
    r.kingOpponent = oppKing;
    r.playerKing = youKing;
    r.betLabel = betLabel();
    return r;
}

void Career::manageReputation(bool won, bool oppCrashed) {
    const Opponent& o = data->opponents[opponentIndex()];
    int r = oppKing ? 100 : o.rep;
    int diff = r - s.rep;
    int m = rng.below(3) + 1;
    if (won) s.rep += diff > 0 ? int(r / 30.0 * m) : int(r / 30.0);
    else if (!oppCrashed && !kingGame) s.rep -= diff < 0 ? int(r / 30.0 * m) : int(r / 30.0);
    s.rep = std::clamp(s.rep, 1, 100);
    if (!s.certificate && s.rep >= 30) { s.certificate = true; awardCertificate = true; }
}

void Career::manageEarnings(bool won, bool oppCrashed) {
    int oi = opponentIndex();
    const Opponent& o = data->opponents[oi];
    if (currentAmount == 2) { // pink slips
        if (won) {
            const Parts& P = data->parts;
            auto t = [](int v, size_t n) { return std::clamp(v - 1, 0, int(n) - 1); };
            int color = opponentColor();
            s.parts[kEngine].push_back({t(o.engine, P.engines.size()), double(10 + rng.below(80)), 1});
            s.parts[kChassis].push_back({t(o.chassis, P.chassis.size()), double(10 + rng.below(80)), color});
            s.parts[kTires].push_back({t(o.wheels, P.tires.size()), double(10 + rng.below(80)), 1});
            s.parts[kAfterburner].push_back({t(o.afterburner, P.afterburners.size()), double(10 + rng.below(80)), 1});
            s.oppColors[oi] = rng.below(colorCount(t(o.chassis, P.chassis.size()))) + 1; // getNewChassisColor
            manageReputation(won, oppCrashed); // sic: a car win counts twice, as in the original
        } else {
            carLost = true;
            for (int k = 0; k < kKinds; k++) {
                auto& v = s.parts[k];
                if (!v.empty()) v.erase(v.begin() + std::clamp(s.current[k], 0, int(v.size()) - 1));
                s.current[k] = 0;
            }
        }
    } else if (currentAmount == 4) { // the crown
        if (youKing) s.cash += 100000;
        if (won) s.youTheKing = true;
        else {
            s.kingKey = o.key;
            s.kingPlanet = o.homePlanet;
            s.youTheKing = false;
        }
    } else {
        if (won) s.cash += currentAmount;
        else if (!oppCrashed) s.cash -= currentAmount;
        if (s.cash < 0) s.cash = 0;
    }
    manageReputation(won, oppCrashed);
}

void Career::storeDamage(const Race& race) {
    bool crash = race.crashed;
    auto cap = [](double& w) { if (w > 100) w = 100; };
    if (OwnedPart* t = s.parts[kTires].empty() ? nullptr : &s.parts[kTires][s.current[kTires]]) {
        if (crash) t->wear = 100;
        else { t->wear += race.wheelDamage / 2; cap(t->wear); }
    }
    double extra = crash ? rng.below(15) + 10 : 0;
    if (!s.parts[kChassis].empty()) {
        OwnedPart& c = s.parts[kChassis][s.current[kChassis]];
        c.wear += (1.2 - rng.unit() * 0.4) * (race.damage + race.wheelDamage / 6) + extra;
        cap(c.wear);
    }
    if (!s.parts[kEngine].empty()) {
        OwnedPart& e = s.parts[kEngine][s.current[kEngine]];
        e.wear += (1.2 - rng.unit() * 0.4) * (race.damage / 3 + race.wheelDamage / 4) + extra / 2;
        cap(e.wear);
    }
}

void Career::settle(const Race& race) {
    bool won = race.raceWon == 1;
    bool crashed = race.crashed && !race.finished;
    int amount = currentAmount;
    bool wasKingGame = kingGame, wasOppKing = oppKing, wasYouKing = youKing;

    // attachFinishMessage / attachCrashMessage
    std::string stake = amount == 2 ? "the car" : "$ " + std::to_string(amount);
    resultWon = won;
    resultHead = won ? "YOU WIN!" : crashed ? "WRECKED!" : "YOU LOSE";
    if (won) {
        std::string bang = "!";
        for (int i = 1; i < amount / 2000; i++) bang += "!";
        resultLine = wasKingGame ? (wasOppKing ? "You are the new King!" : "You have retained your crown")
                                 : "you win " + stake + " " + bang;
    } else if (wasKingGame) {
        resultLine = wasOppKing ? "You have lost the challenge." : "You have lost your crown.";
    } else if (crashed && race.oppCrashed && amount != 2) {
        resultLine = "your rival crashed too. no money changes hands.";
    } else {
        resultLine = "you lose " + stake + ".";
    }
    if (wasYouKing) resultLine += "  + $ 100000 challenge fee";

    manageEarnings(won, race.oppCrashed);
    if (!wasYouKing && !carLost) {
        // initAfterburner(): fuel used becomes afterburner wear; then storeDamage().
        // (The original also ran these after losing the car, damaging whichever spare moved into slot 0.)
        if (!s.parts[kAfterburner].empty() && race.boostTotal > 0)
            s.parts[kAfterburner][s.current[kAfterburner]].wear = 100 - roundAS(double(race.boostLeft) / race.boostTotal * 100);
        storeDamage(race);
    }

    Trouble t = checkForTrouble(race.crashed);
    if (wasKingGame && !won && !wasYouKing) quitToGarage(t);       // lost the challenge: home
    else if (wasKingGame && !won && wasYouKing) quitToGarage(t);   // lost the crown: home
    else if (t != Trouble::None) quitToGarage(t);
    else if (!kingGame) { afterRace = true; nextInOrder(); enterPlanet(); }
    else { afterRace = false; enterPlanet(); }
}

// ---- saves ---------------------------------------------------------------------------

static const char* kKindKeys[kKinds] = {"engines", "tires", "chassis", "afterburners"};

std::string Career::toJson() const {
    json j;
    j["version"] = 1;
    j["name"] = s.name;
    j["difficulty"] = s.difficulty;
    j["cash"] = s.cash;
    j["rep"] = s.rep;
    j["time"] = s.time;
    j["certificate"] = s.certificate;
    j["youTheKing"] = s.youTheKing;
    j["king"] = {{"planet", s.kingPlanet}, {"key", s.kingKey}};
    for (int k = 0; k < kKinds; k++) {
        json arr = json::array();
        for (auto& p : s.parts[k]) {
            json e = {{"type", p.type}, {"wear", std::round(p.wear * 1000) / 1000}};
            if (k == kChassis) e["color"] = p.color;
            arr.push_back(e);
        }
        j["parts"][kKindKeys[k]] = arr;
        j["currentParts"][kKindKeys[k]] = s.current[k];
        j["shopStock"][kKindKeys[k]] = s.stock[k];
    }
    j["opponentColors"] = s.oppColors;
    j["planetOpponents"] = std::vector<int>(s.planetOpponents + 1, s.planetOpponents + 6);
    j["noTravelMessage"] = s.noTravelMessage;
    return j.dump(2);
}

bool Career::fromJson(const std::string& text, std::string& err) {
    try {
        json j = json::parse(text);
        CareerState n;
        n.name = j.at("name").get<std::string>();
        n.difficulty = std::clamp(j.value("difficulty", 1), 0, 2);
        n.diffFactor = 1 + (n.difficulty - 1) / 5.0;
        n.cash = std::max(0, j.value("cash", 0));
        n.rep = std::clamp(j.value("rep", 15), 1, 100);
        n.time = j.value("time", 0);
        n.certificate = j.value("certificate", false);
        n.youTheKing = j.value("youTheKing", false);
        if (j.contains("king")) { n.kingPlanet = j["king"].value("planet", 3); n.kingKey = j["king"].value("key", 0); }
        const Parts& P = data->parts;
        const int sizes[kKinds] = {int(P.engines.size()), int(P.tires.size()), int(P.chassis.size()), int(P.afterburners.size())};
        for (int k = 0; k < kKinds; k++) {
            for (auto& e : j.at("parts").at(kKindKeys[k])) {
                OwnedPart p;
                p.type = e.at("type").get<int>();
                if (p.type < 0 || p.type >= sizes[k]) continue; // a part a mod removed
                p.wear = std::clamp(e.value("wear", 0.0), 0.0, 100.0);
                p.color = k == kChassis ? std::clamp(e.value("color", 1), 1, colorCount(p.type)) : 1;
                n.parts[k].push_back(p);
            }
            int c = j.contains("currentParts") ? j["currentParts"].value(kKindKeys[k], 0) : 0;
            n.current[k] = n.parts[k].empty() ? 0 : std::clamp(c, 0, int(n.parts[k].size()) - 1);
            n.stock[k].assign(sizes[k], 0);
            if (j.contains("shopStock") && j["shopStock"].contains(kKindKeys[k])) {
                auto v = j["shopStock"][kKindKeys[k]].get<std::vector<int>>();
                for (int i = 0; i < sizes[k] && i < int(v.size()); i++) n.stock[k][i] = std::max(0, v[i]);
            }
        }
        for (size_t i = 0; i < data->opponents.size(); i++) n.oppColors.push_back(data->opponents[i].color);
        if (j.contains("opponentColors")) {
            auto v = j["opponentColors"].get<std::vector<int>>();
            for (size_t i = 0; i < v.size() && i < n.oppColors.size(); i++) n.oppColors[i] = v[i];
        }
        if (j.contains("planetOpponents")) {
            auto v = j["planetOpponents"].get<std::vector<int>>();
            for (int i = 0; i < 5 && i < int(v.size()); i++) n.planetOpponents[i + 1] = std::max(1, v[i]);
        }
        n.noTravelMessage = j.value("noTravelMessage", false);
        s = n;
    } catch (const std::exception& e) {
        err = e.what();
        return false;
    }
    planet = 0;
    encounter = Encounter::None;
    trouble = Trouble::None;
    awardCertificate = false;
    return true;
}
