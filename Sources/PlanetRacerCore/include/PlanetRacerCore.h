// Plain C interface to the Planet Racer game core (C++). Swift imports this module directly.
// Everything here is plain data: no C++ types cross the boundary.
#ifndef PLANET_RACER_CORE_H
#define PLANET_RACER_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PRGame PRGame;

// ---- lifetime / catalog -------------------------------------------------------------
PRGame* pr_create(const char* dataDir);    // never NULL; check pr_error()
void pr_destroy(PRGame* g);
const char* pr_error(const PRGame* g);     // "" when loaded fine

typedef struct {
    int id;
    const char* name;
    const char* description;
    const char* image;      // menu globe, assets/ui/<image>.png
    const char* buildings;  // scenery frame label
    double surface, gravity, size, difficulty;
    uint32_t fill, line;    // 0xRRGGBB
} PRPlanetInfo;

typedef struct {
    const char* name;
    int homePlanet, rep, chassis, wheels, engine, afterburner, color;
    int face, faceFrame;   // portrait: assets/sprites/faces/face<face>_<faceFrame>.png
} PROpponentInfo;

enum { PR_ENGINE = 0, PR_TIRES = 1, PR_CHASSIS = 2, PR_AFTERBURNER = 3 };
typedef struct {
    const char* name;
    double value;   // engine/chassis: speed, tires: grip (contact damping), afterburner: seconds
    int price, art, colors;
} PRPartInfo;

int pr_planet_count(const PRGame* g);
PRPlanetInfo pr_planet(const PRGame* g, int i);
int pr_opponent_count(const PRGame* g);
PROpponentInfo pr_opponent(const PRGame* g, int i);
int pr_part_count(const PRGame* g, int kind);
PRPartInfo pr_part(const PRGame* g, int kind, int i);
uint32_t pr_wheel_tint(const PRGame* g, int chassis, int color); // 0xRRGGBB
double pr_top_speed(const PRGame* g, int engine, int chassis);   // as a fraction of the cap (0..1)

// ---- race ----------------------------------------------------------------------------
typedef struct { int planet, opponent, engine, tires, chassis, afterburner, color, difficulty; } PRRaceConfig;
typedef struct { bool up, down, left, right, boost; } PRInput;

enum { PR_RUNNING = 0, PR_WON = 1, PR_LOST = 2, PR_CRASHED = 3 };
enum { PR_SFX_START = 0, PR_SFX_HIT_GROUND, PR_SFX_HIT_ROOF, PR_SFX_CRASH, PR_SFX_FINISH, PR_SFX_LOSE, PR_SFX_AMBIENT };

#define PR_MAX_POINTS 16
typedef struct { double x, y, r, rimX, rimY; bool wheel; } PRPoint;
typedef struct { double x, y; int frame; double distance; } PRStar;   // screen-space game units
typedef struct { double x, y; int frame; } PRTile;                     // world units
typedef struct { double x0, y0, x1, y1; } PRSegment;

typedef struct {
    int pointCount;
    PRPoint car[PR_MAX_POINTS], opp[PR_MAX_POINTS];
    int bodyA, bodyB;               // point indices defining the chassis angle
    int bodyIdx[4];                 // points averaged for the chassis position
    int bodyCount;
    double camX, camY;              // top-left of the view in world units
    bool started, crashed, finished, oppVisible, oppBurning, boosting, engineOn;
    int result;                     // PR_RUNNING ...
    double boostFraction, damageFlash, damage, raceTime;
    double playerProgress, oppProgress; // 0..1 around the planet
    double musicFade;               // 0..1
    int engineSound;
    double planetSize, finishGroundY;
    bool showStartBuildings;
    int chassisArt, color, tireArt, oppChassisArt, oppColor, oppTireArt;
    uint32_t wheelTint, oppWheelTint;
    bool oppKingmobile, playerKingmobile;
} PRFrame;

void pr_race_begin(PRGame* g, PRRaceConfig cfg);
void pr_race_set_view(PRGame* g, double width, double height); // visible game units
void pr_race_start(PRGame* g);                                  // "press any key"
void pr_race_tick(PRGame* g, PRInput in);                       // one original frame (1/36 s)
void pr_race_abandon(PRGame* g);                                // the HUD's EXIT
void pr_race_frame(const PRGame* g, PRFrame* out);
int pr_race_segments(const PRGame* g, PRSegment* out, int max);
int pr_race_stars(const PRGame* g, PRStar* out, int max);
int pr_race_tiles(const PRGame* g, PRTile* out, int max);
bool pr_race_poll_sfx(PRGame* g, int* id, float* volume);
double pr_ground_y(const PRGame* g, double x);
double pr_ground_slope(const PRGame* g, double x);              // degrees
const char* pr_race_opponent_name(const PRGame* g);
const char* pr_race_planet_name(const PRGame* g);
int pr_race_planet_index(const PRGame* g);                      // the race's planet, for pr_planet()
double pr_tick_seconds(void);
const char* pr_race_bet_label(const PRGame* g);                 // "QUICK RACE", "$ 500", "CAR", "CROWN"

// ---- career --------------------------------------------------------------------------
// The original career rules live in the core; the app only shows state and sends choices.
// Every call that changes state returns quickly; save with pr_career_to_json afterwards.

enum { PR_OK = 0, PR_NOT_ENOUGH_CASH = 1, PR_NEED_CERTIFICATE = 2, PR_NOTHING = 3 };
enum { PR_TROUBLE_NONE = 0, PR_TROUBLE_CAR_LOST, PR_TROUBLE_TIME, PR_TROUBLE_DAMAGE };
enum {
    PR_ENC_NONE = 0,       // at home (garage, shop, planet select)
    PR_ENC_WAIT_KING,      // you are the King: wait for a challenger
    PR_ENC_VEHICLE_UPDATE, // after a race: damage summary
    PR_ENC_OFFER,          // the rival's bet: accept / decline / adjust / race for the car
    PR_ENC_ACCEPTED,       // negotiation accepted: race
    PR_ENC_DECLINED,       // negotiation declined: OK, the rival leaves
    PR_ENC_REFUSED,        // the rival won't race you; leaves after 2 s
    PR_ENC_NO_CASH,        // you can't cover the bet
};

typedef struct { int type; double wear; int color; } PROwnedPart; // type indexes pr_part(); wear 0..100

typedef struct {
    const char* name;
    int difficulty, cash, rep, trips;   // rep 1..100 (shown as rep/10)
    bool certificate, youTheKing, noTravelMessage;
    int planet;                         // planet id 1..5 while away, 0 at home
    int planetTime, timeLimit;          // 20 encounters and races, then it's time to go home
    int kingOpponent;                   // data index of the current King (-1 when it's you)
} PRCareerInfo;

typedef struct {
    int state;                          // PR_ENC_*
    int opponent;                       // data index (pr_opponent)
    const char* sentence;
    int amount, initialAmount;          // 2 = the car, 4 = the crown, else dollars
    bool negotiating, kingGame, oppKing, youKing;
    int oppColor;                       // the rival's current paint
} PREncounter;

void pr_career_new(PRGame* g, const char* name, int difficulty);  // createNewGame
bool pr_career_load_json(PRGame* g, const char* json);            // false: see pr_career_error
const char* pr_career_error(const PRGame* g);
const char* pr_career_to_json(PRGame* g);                         // valid until the next call
bool pr_career_start_garage(PRGame* g);                           // true: the King flow starts (Moon)
PRCareerInfo pr_career_info(const PRGame* g);

int pr_career_part_count(const PRGame* g, int kind);
int pr_career_current(const PRGame* g, int kind);
PROwnedPart pr_career_part(const PRGame* g, int kind, int index);
void pr_career_select(PRGame* g, int kind, int delta);            // garage arrows, no wrap
int pr_career_repair_price(const PRGame* g, int kind);
int pr_career_repair(PRGame* g, int kind);                        // PR_OK / PR_NOT_ENOUGH_CASH / PR_NOTHING
bool pr_career_can_race(const PRGame* g);
double pr_career_speed_stat(const PRGame* g);                     // garage bars, 0..1
double pr_career_grip_stat(const PRGame* g);

int pr_career_stock(const PRGame* g, int kind, int type);
int pr_career_buy(PRGame* g, int kind, int type, int color);
int pr_career_sell_value(const PRGame* g, int kind, int index);
void pr_career_sell(PRGame* g, int kind, int index);

int pr_career_travel_cost(const PRGame* g, int planetId);
int pr_career_opponents_on(const PRGame* g, int planetId);
int pr_career_travel(PRGame* g, int planetId);                    // PR_OK / NOT_ENOUGH_CASH / NEED_CERTIFICATE
void pr_career_set_no_travel_message(PRGame* g, bool on);

PREncounter pr_career_encounter(const PRGame* g);
void pr_career_adjust_amount(PRGame* g, int dir);
void pr_career_offer_car(PRGame* g);
bool pr_career_accept(PRGame* g);                                 // true: start the race now
void pr_career_decline(PRGame* g);
void pr_career_continue(PRGame* g);                               // OK on the non-offer panels
void pr_career_refusal_elapsed(PRGame* g);
bool pr_career_go_home(PRGame* g);                                // true: to the title (King game)
int pr_career_take_trouble(PRGame* g);                            // PR_TROUBLE_*, once
bool pr_career_take_certificate(PRGame* g);                       // true once when awarded

void pr_career_race_begin(PRGame* g);                             // like pr_race_begin, from the career
void pr_career_race_settle(PRGame* g);                            // once the race is over: money, wear, next
const char* pr_career_result_head(const PRGame* g);
const char* pr_career_result_line(const PRGame* g);

#ifdef __cplusplus
}
#endif
#endif
