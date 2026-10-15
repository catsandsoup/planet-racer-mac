#include "data.hpp"
#include <nlohmann/json.hpp>
#include <cmath>
#include <fstream>
#include <sstream>

using nlohmann::json;

static Rgb parseColor(const json& j) {
    Rgb c;
    if (!j.is_string()) return c;
    std::string s = j.get<std::string>();
    if (!s.empty() && s[0] == '#') s = s.substr(1);
    unsigned v = std::stoul(s, nullptr, 16);
    c.r = (v >> 16) & 255; c.g = (v >> 8) & 255; c.b = v & 255;
    return c;
}

static bool readJson(const std::string& path, json& out, std::string& err) {
    std::ifstream f(path);
    if (!f) { err = "cannot open " + path; return false; }
    try { out = json::parse(f, nullptr, true, /*ignore_comments=*/true); }
    catch (const std::exception& e) { err = path + ": " + e.what(); return false; }
    return true;
}

bool GameData::loadMap(const std::string& path, std::vector<std::pair<double, double>>& pts, std::string& err) {
    json j;
    if (!readJson(path, j, err)) return false;
    pts.clear();
    for (auto& p : j.at("points")) pts.emplace_back(p.at(0).get<double>(), p.at(1).get<double>());
    if (pts.size() < 2) { err = path + ": a map needs at least 2 points"; return false; }
    return true;
}

bool GameData::saveMap(const std::string& path, const std::string& name, const std::vector<std::pair<double, double>>& pts) {
    json j;
    j["name"] = name;
    j["points"] = json::array();
    for (auto& p : pts) j["points"].push_back({std::round(p.first), std::round(p.second)});
    std::ofstream f(path);
    if (!f) return false;
    f << j.dump(2) << "\n";
    return true;
}

bool GameData::load(const std::string& dir, std::string& err) {
    json jp, jpl, jo, jc;
    if (!readJson(dir + "/parts.json", jp, err) || !readJson(dir + "/planets.json", jpl, err) ||
        !readJson(dir + "/opponents.json", jo, err) || !readJson(dir + "/cars/default.json", jc, err))
        return false;
    try {
        for (auto& e : jp.at("engines"))
            parts.engines.push_back({e.value("id", ""), e.at("name"), e.at("speed"), e.value("price", 0), e.value("sound", 1)});
        for (auto& e : jp.at("tires"))
            parts.tires.push_back({e.value("id", ""), e.at("name"), e.at("grip"), e.value("price", 0), e.value("art", 1)});
        for (auto& e : jp.at("chassis")) {
            ChassisPart c{e.value("id", ""), e.at("name"), e.at("speed"), e.value("price", 0), e.value("art", 1), {}};
            for (auto& t : e.value("wheelTints", json::array())) c.wheelTints.push_back(parseColor(t));
            parts.chassis.push_back(c);
        }
        for (auto& e : jp.at("afterburners"))
            parts.afterburners.push_back({e.value("id", ""), e.at("name"), e.at("seconds"), e.value("price", 0)});

        for (auto& e : jpl.at("planets")) {
            Planet p;
            p.id = e.at("id"); p.name = e.at("name"); p.description = e.value("description", "");
            p.buildings = e.value("buildings", "buildings3"); p.map = e.value("map", ""); p.image = e.value("image", "planet_purple");
            p.surface = e.at("surface"); p.gravity = e.at("gravity"); p.size = e.at("size");
            p.difficulty = e.at("difficulty"); p.travelCost = e.value("travelCost", 0);
            p.fill = parseColor(e.at("fillColor")); p.line = parseColor(e.at("lineColor"));
            if (!p.map.empty() && !loadMap(dir + "/" + p.map, p.mapPoints, err)) return false;
            planets.push_back(p);
        }
        for (auto& e : jo.at("opponents")) {
            Opponent o;
            o.name = e.at("name"); o.homePlanet = e.at("homePlanet"); o.key = e.value("key", 0); o.face = e.value("face", 1); o.faceFrame = e.value("faceframe", 1);
            o.rep = e.at("rep"); o.chassis = e.at("chassis"); o.wheels = e.at("wheels"); o.engine = e.at("engine");
            o.afterburner = e.at("afterburner"); o.temper = e.value("temper", 0); o.color = e.value("color", 1);
            opponents.push_back(o);
        }

        car.rearRadius = jc.at("wheelRadius").at("rear"); car.frontRadius = jc.at("wheelRadius").at("front");
        car.stiffness = jc.value("stiffness", 0.55);
        for (auto& p : jc.at("points")) {
            std::string w = p.value("wheel", "");
            car.points.push_back({p.at("x"), p.at("y"), p.at("gravityMul"), p.value("collide", true), w == "rear" ? 1 : w == "front" ? 2 : 0});
        }
        for (auto& s : jc.at("springs")) car.springs.emplace_back(s.at(0).get<int>(), s.at(1).get<int>());
        car.breakOnCrash = jc.value("breakOnCrash", std::vector<int>{});
        car.bodyPoints = jc.value("bodyPoints", std::vector<int>{2, 3, 4, 5});
        auto angle = [](const json& j, AngleCheck& a) {
            a.vertex = j.at("vertex"); a.a = j.at("a"); a.b = j.at("b");
            a.min = j.value("min", -1e9); a.max = j.value("max", 1e9);
        };
        angle(jc.at("koAngle"), car.ko);
        angle(jc.at("flipAngle"), car.flip);
    } catch (const std::exception& e) {
        err = std::string("data error: ") + e.what();
        return false;
    }
    json jr;
    std::string rerr;
    if (readJson(dir + "/rivals.json", jr, rerr)) {
        for (auto it = jr.begin(); it != jr.end(); ++it)
            if (it.value().is_array())
                for (auto& l : it.value()) if (l.is_string()) lines[it.key()].push_back(l.get<std::string>());
    }
    if (parts.engines.empty() || parts.tires.empty() || parts.chassis.empty() || parts.afterburners.empty() || planets.empty()) {
        err = "parts.json / planets.json must define at least one of each item";
        return false;
    }
    return true;
}
