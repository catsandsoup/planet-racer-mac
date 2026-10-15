// Game data loaded from data/*.json. Everything here is moddable without recompiling.
#pragma once
#include <string>
#include <vector>
#include <cstdint>
#include <map>

struct Rgb { uint8_t r = 255, g = 255, b = 255; };

struct EnginePart { std::string id, name; double speed = 1; int price = 0; int sound = 1; };
struct TirePart { std::string id, name; double grip = 0.02; int price = 0; int art = 1; };
struct ChassisPart { std::string id, name; double speed = 1; int price = 0; int art = 1; std::vector<Rgb> wheelTints; };
struct AfterburnerPart { std::string id, name; double seconds = 10; int price = 0; };

struct Parts {
    std::vector<EnginePart> engines;
    std::vector<TirePart> tires;
    std::vector<ChassisPart> chassis;
    std::vector<AfterburnerPart> afterburners;
};

struct Planet {
    int id = 0;
    std::string name, description, buildings, map, image;
    double surface = 50, gravity = 0.24, size = 8000, difficulty = 0.9;
    int travelCost = 0;
    Rgb fill, line;
    std::vector<std::pair<double, double>> mapPoints; // filled when 'map' is set
};

struct Opponent {
    std::string name;
    int homePlanet = 1, key = 0, face = 1, faceFrame = 1, rep = 50, chassis = 1, wheels = 1, engine = 1, afterburner = 1, temper = 0, color = 1;
};

struct CarPoint { double x, y, gravityMul; bool collide; int wheel; }; // wheel: 0 none, 1 rear, 2 front
struct AngleCheck { int vertex = 1, a = 0, b = 4; double min = -1e9, max = 1e9; };
struct CarDef {
    double rearRadius = 23, frontRadius = 17, stiffness = 0.55;
    std::vector<CarPoint> points;
    std::vector<std::pair<int, int>> springs;
    std::vector<int> breakOnCrash, bodyPoints;
    AngleCheck ko, flip;
};

struct GameData {
    Parts parts;
    std::vector<Planet> planets;
    std::vector<Opponent> opponents;
    CarDef car;
    std::map<std::string, std::vector<std::string>> lines; // data/rivals.json (optional)
    bool load(const std::string& dataDir, std::string& err);
    static bool loadMap(const std::string& path, std::vector<std::pair<double, double>>& pts, std::string& err);
    static bool saveMap(const std::string& path, const std::string& name, const std::vector<std::pair<double, double>>& pts);
};
