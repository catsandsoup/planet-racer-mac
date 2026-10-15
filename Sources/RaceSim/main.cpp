// Headless race simulator: drives the game core through the same C interface the app uses,
// with a simple autopilot. usage: RaceSim <data dir> [races per planet] [v]
// Fails (exit 1) on NaNs or when a planet's races never finish.
#include "PlanetRacerCore.h"
#include <cmath>
#include <cstdio>
#include <string>

// Plays a whole career with the autopilot: travel, bets, races, repairs, saves. Fails on broken invariants.
static int careerSim(PRGame* g, int races) {
    int failures = 0;
    pr_career_new(g, "Sim", 1);
    PRFrame f;
    int raced = 0, trips = 0, won = 0;
    for (int step = 0; step < 4000 && raced < races; step++) {
        PRCareerInfo ci = pr_career_info(g);
        if (ci.cash < 0 || ci.rep < 1 || ci.rep > 100) { std::printf("bad cash/rep %d %d\n", ci.cash, ci.rep); failures++; break; }
        for (int k = 0; k < 4; k++)
            for (int i = 0; i < pr_career_part_count(g, k); i++) {
                double w = pr_career_part(g, k, i).wear;
                if (!(w >= 0 && w <= 100)) { std::printf("bad wear %f\n", w); failures++; }
            }
        if (ci.planet == 0) {
            pr_career_take_trouble(g);
            for (int k = 0; k < 4; k++) { pr_career_repair(g, k); }
            if (!pr_career_can_race(g)) {
                for (int k = 0; k < 4; k++)
                    if (pr_career_part_count(g, k) == 0) pr_career_buy(g, k, 0, 1);
                if (!pr_career_can_race(g)) { std::printf("career stuck: broke after %d races\n", raced); break; }
            }
            int planet = ci.certificate ? 1 + (trips % 4) : 3 + (trips % 2);
            if (pr_career_travel(g, planet) != PR_OK && pr_career_travel(g, 3) != PR_OK) { std::printf("can't afford travel\n"); break; }
            trips++;
            continue;
        }
        PREncounter e = pr_career_encounter(g);
        if (e.state == PR_ENC_OFFER || e.state == PR_ENC_ACCEPTED) {
            if (e.state == PR_ENC_OFFER && e.amount > 4 && step % 3 == 0) pr_career_adjust_amount(g, 1);
            if (!pr_career_accept(g)) continue;
            pr_career_race_begin(g);
            pr_race_set_view(g, 711, 400);
            pr_race_start(g);
            for (int t = 0; t < 36 * 400; t++) {
                pr_race_frame(g, &f);
                if (f.result != PR_RUNNING) break;
                double bx = 0;
                for (int i = 0; i < f.bodyCount; i++) bx += f.car[f.bodyIdx[i]].x;
                bx /= f.bodyCount;
                const PRPoint &a = f.car[f.bodyA], &b = f.car[f.bodyB];
                double ang = std::atan2(b.y - a.y, b.x - a.x) * 180 / M_PI - pr_ground_slope(g, bx);
                pr_race_tick(g, PRInput{true, false, ang > 6, ang < -6, t % 90 < 20});
            }
            pr_race_frame(g, &f);
            if (f.result == PR_RUNNING) pr_race_abandon(g);
            if (f.result == PR_WON) won++;
            pr_career_race_settle(g);
            raced++;
        } else if (e.state != PR_ENC_NONE) {
            pr_career_continue(g);
        }
        if (step % 25 == 0) { // save / load round trip mid-career
            std::string a = pr_career_to_json(g);
            if (!pr_career_load_json(g, a.c_str())) { std::printf("load failed: %s\n", pr_career_error(g)); failures++; break; }
            std::string b = pr_career_to_json(g);
            if (a != b) { std::printf("save round trip differs\n"); failures++; break; }
            if (ci.planet != 0 && !ci.youTheKing) continue; // loading puts you at home
        }
    }
    PRCareerInfo ci = pr_career_info(g);
    std::printf("career: %d races, %d won, %d trips, cash $%d, rep %d/10, certificate %s, king %s\n", raced, won, trips,
                ci.cash, ci.rep / 10, ci.certificate ? "yes" : "no", ci.youTheKing ? "yes" : "no");
    if (raced == 0) failures++;
    return failures;
}

int main(int argc, char** argv) {
    std::string dir = argc > 1 ? argv[1] : "data";
    int runs = argc > 2 ? std::stoi(argv[2]) : 20;
    bool verbose = argc > 3;
    PRGame* g = pr_create(dir.c_str());
    if (*pr_error(g)) { std::fprintf(stderr, "load failed: %s\n", pr_error(g)); return 2; }

    int failures = 0;
    std::printf("%-24s %5s %5s %5s %5s %8s %8s\n", "planet", "won", "lost", "crash", "stuck", "avg sec", "opp sec");
    PRFrame f;
    for (int pi = 0; pi < pr_planet_count(g); pi++) {
        int won = 0, lost = 0, crashed = 0, stuck = 0, finished = 0, oppDone = 0;
        double secs = 0, oppSecs = 0;
        for (int run = 0; run < runs; run++) {
            PRRaceConfig c{pi, run % pr_opponent_count(g), 2, 2, 2, 2, 1, 1}; // best parts: the autopilot is clumsy
            pr_race_begin(g, c);
            pr_race_set_view(g, 711, 400); // 16:9
            pr_race_start(g);
            int ticks = 0, oppTick = -1;
            bool nan = false;
            for (; ticks < 36 * 600; ticks++) {
                pr_race_frame(g, &f);
                if (f.result != PR_RUNNING) break;
                double bx = 0, by = 0;
                for (int i = 0; i < f.bodyCount; i++) { bx += f.car[f.bodyIdx[i]].x; by += f.car[f.bodyIdx[i]].y; }
                bx /= f.bodyCount;
                const PRPoint &a = f.car[f.bodyA], &b = f.car[f.bodyB];
                double e = std::atan2(b.y - a.y, b.x - a.x) * 180 / M_PI - pr_ground_slope(g, bx);
                pr_race_tick(g, PRInput{true, false, e > 6, e < -6, false});
                pr_race_frame(g, &f);
                if (oppTick < 0 && f.oppProgress >= 1) oppTick = ticks;
                if (!std::isfinite(f.car[0].x) || !std::isfinite(f.car[0].y)) { nan = true; break; }
            }
            if (nan) { std::printf("NaN on planet %d run %d\n", pi, run); failures++; }
            if (verbose && f.result == PR_CRASHED) {
                std::printf("  crash at %.0f%% t=%.1fs\n", 100 * f.playerProgress, ticks / 36.0);
            }
            for (int extra = 0; oppTick < 0 && extra < 36 * 600; extra++) {
                pr_race_tick(g, PRInput{});
                pr_race_frame(g, &f);
                if (f.oppProgress >= 1) oppTick = ticks + extra;
            }
            if (oppTick >= 0) { oppDone++; oppSecs += oppTick / 36.0; }
            pr_race_frame(g, &f);
            switch (f.result) {
            case PR_WON: won++; break;
            case PR_LOST: lost++; break;
            case PR_CRASHED: crashed++; break;
            default: stuck++;
            }
            if (f.finished) { finished++; secs += ticks / 36.0; }
        }
        std::printf("%-24s %5d %5d %5d %5d %8.1f %8.1f\n", pr_planet(g, pi).name, won, lost, crashed, stuck,
                    finished ? secs / finished : 0.0, oppDone ? oppSecs / oppDone : 0.0);
        if (stuck == runs) failures++;
    }
    failures += careerSim(g, runs * 3);
    pr_destroy(g);
    return failures ? 1 : 0;
}
