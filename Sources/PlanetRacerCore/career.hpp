// The career: garage, wear and repairs, the parts shop, travel, rival encounters with betting and
// pink slips, reputation, the certificate and the King of the Moon. Ported from the original
// control-centre and opponent-select code (createNewGame, initGarage, clickOkRepair, beginShopItems,
// sellItem/buyItem, clickOkTravel, initOpponents, manageAmount/negotiate, manageEarnings,
// manageReputation, storeDamage, initAfterburner, checkForTrouble).
// No UI here: the app asks for state and sends the player's choices.
#pragma once
#include "data.hpp"
#include "physics.hpp"
#include "race.hpp"
#include <string>
#include <vector>

// Part kinds, same numbering as PR_ENGINE.. in the C API.
enum PartKind { kEngine = 0, kTires = 1, kChassis = 2, kAfterburner = 3, kKinds = 4 };

struct OwnedPart { int type = 0; double wear = 0; int color = 1; }; // color: chassis paint only

/// Everything the original kept in _global.game (one saved career).
struct CareerState {
    std::string name;
    int difficulty = 1;            // 0 easy, 1 medium, 2 hard (_global.difficulty)
    double diffFactor = 1;         // 1 + (difficulty - 1) / 5
    int cash = 10000;
    int rep = 15;                  // 1..100, shown as rep/10
    int time = 0;                  // trips home (game.time)
    bool certificate = false;      // needed for planets 1 and 2 (rep >= 30)
    bool youTheKing = false;
    int kingPlanet = 3, kingKey = 0; // who wears the crown (starts as Gertrude of planet 3)
    std::vector<OwnedPart> parts[kKinds];
    int current[kKinds] = {0, 0, 0, 0};
    std::vector<int> stock[kKinds];  // shop stock per catalogue item
    std::vector<int> oppColors;      // paint per opponent (data index); changes when you win their car
    int planetOpponents[6] = {0, 0, 0, 0, 0, 1}; // rivals waiting on planets 1..5 (newPlanetData)
    bool noTravelMessage = false;
};

enum class Encounter {
    None,          // not on a planet
    WaitKing,      // you are the King: "wait for a challenger"
    VehicleUpdate, // after a race: the damage summary
    Offer,         // the rival's panel: race for money / the car / the crown
    Accepted,      // negotiation accepted: race
    Declined,      // negotiation declined: the rival leaves
    Refused,       // the rival will not race you (decline/temper/chicken lines); leaves after 2 s
    NoCash,        // you accepted a bet you cannot cover
};

enum class Trouble { None, CarLost, Time, Damage };

enum class ActionResult { Ok, NotEnoughCash, NeedCertificate, Nothing };

class Career {
public:
    const GameData* data = nullptr;
    CareerState s;
    Rng rng;

    // ---- session on a planet (the original's runtime globals; not saved)
    int planet = 0;               // planet id 1..5, 0 = at home in the control centre
    int planetTime = 0;           // _global.planetTime: 20 and it's time to go home
    int nrOfOpponents = 0;
    bool kingGame = false, oppKing = false, youKing = false, afterRace = false, carLost = false;
    std::vector<int> opponents;   // aOpponents: data indices
    std::vector<int> tempers;     // their temper, raised when you waste their time
    std::vector<int> order;       // aRandomOpponents (indices into `opponents`)
    int orderIndex = 0, currentOpponent = 0;
    Encounter encounter = Encounter::None;
    std::string sentence;
    int initialAmount = 0, currentAmount = 0;
    bool negotiating = false;
    double afw = -1;              // negotiation tolerance (null = -1)
    double aiSpeed = 1, playerSpeed = 1;

    // ---- messages for the garage (clickOkAfterRace, the certificate)
    Trouble trouble = Trouble::None;
    bool awardCertificate = false;

    // ---- the last race's outcome text (attachFinishMessage)
    std::string resultHead, resultLine;
    bool resultWon = false;

    void bind(const GameData& d) { data = &d; }
    void newGame(const std::string& name, int difficulty);       // createNewGame
    bool startGarage();                                          // true when the King flow starts instead

    // garage
    int count(int kind) const { return int(s.parts[kind].size()); }
    const OwnedPart* currentPart(int kind) const;
    void select(int kind, int delta);                            // garage arrows (no wrap)
    int repairPrice(int kind) const;                             // clickOkRepair
    ActionResult repair(int kind);
    bool allPartsPresent() const;                                // checkAllPartsPresent
    bool noBadDamage() const;                                    // checkForDamage
    bool canRace() const { return allPartsPresent() && noBadDamage(); }
    double speedStat() const;                                    // initCarStats, 0..1
    double gripStat() const;

    // shop
    int partPrice(int kind, int type) const;
    std::string partName(int kind, int type) const;
    int colorCount(int chassisType) const;
    ActionResult buy(int kind, int type, int color);
    int sellValue(int kind, int index) const;
    void sell(int kind, int index);

    // travel
    int planetIndex(int id) const;                               // data index of planet id, -1 if none
    int travelCost(int id) const;
    int opponentsOn(int id) const { return id == 5 ? 1 : (id >= 1 && id <= 5 ? s.planetOpponents[id] : 0); }
    ActionResult travel(int id);                                 // clickOkTravel's OK

    // rival encounter
    int opponentIndex() const;                                   // data index of the rival in front of you
    int opponentTemper() const { return tempers.empty() ? 0 : tempers[currentOpponent]; }
    int opponentColor() const;
    void advanceEncounter();                                     // OK / wait / continue on non-offer panels
    void adjustAmount(int dir);                                  // manageAmount up/down
    void offerCar();                                             // manageAmount("car")
    bool accept();                                               // true = race now
    void decline();
    void goHomeButton(bool& toTitle);                            // mcGoHome
    void tickRefusal();                                          // the 2 s opponentWaitInt elapsed

    // race
    RaceSetup raceSetup();                                       // start(): also counts toward the time limit
    void settle(const Race& race);                               // finish: manageEarnings, wear, next step
    std::string betLabel() const;

    // saves
    std::string toJson() const;
    bool fromJson(const std::string& text, std::string& err);

private:
    void initOpponents(int planetId);
    void enterPlanet();                                          // startOppSelect
    void arrive();                                               // moveOppSelect: a rival pulls up
    void openOffer();                                            // attachOpponentPanel
    void leave();                                                // the rival drives off
    void nextInOrder();
    void initSession();                                          // init()
    void computeSpeeds();                                        // setupVehicle's AISpeed / playerSpeed
    int setAmount();                                             // manageAmount("setamount")
    bool negotiate(int amount);
    Trouble checkForTrouble(bool crashed) const;
    void quitToGarage(Trouble t);
    void manageEarnings(bool won, bool oppCrashed);
    void manageReputation(bool won, bool oppCrashed);
    void storeDamage(const Race& race);
    void refillShop();                                           // beginShopItems
    void newPlanetData();
    std::string sentenceFor(const char* kind);
    int dataOpponent(int planetId, int key) const;
};
