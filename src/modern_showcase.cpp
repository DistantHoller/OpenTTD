/* Opt-in development fixture, added 2026-10-12. GPL-2.0-only. */
#include "stdafx.h"
#include "modern_showcase.h"
#include "command_func.h"
#include "company_func.h"
#include "company_base.h"
#include "vehicle_base.h"
#include "rail_cmd.h"
#include "station_cmd.h"
#include "station_map.h"
#include "station_func.h"
#include "newgrf_station.h"
#include "terraform_cmd.h"
#include "landscape_cmd.h"
#include "town_cmd.h"
#include "vehicle_cmd.h"
#include "train_cmd.h"
#include "order_cmd.h"
#include "order_base.h"
#include "viewport_func.h"
#include "saveload/saveload_func.h"
#include "strings_func.h"
#include "network/network.h"
#include "signal_func.h"
#include "landscape.h"
#include "house.h"
#include "town_map.h"
#include "road_cmd.h"
#include "road_map.h"
#include "engine_base.h"
#include "engine_func.h"
#include "core/backup_type.hpp"
#include <fstream>
#include "safeguards.h"

extern Company *DoStartupNewCompany(bool, CompanyID);
static VehicleID _showcase_train = VehicleID::Invalid();
static std::string _showcase_log;
static bool _showcase_ok = false;

static bool Check(std::string_view action, const CommandCost &cost)
{
	/* Direct development commands bypass DoCommandP's normal signal flush.
	 * Complete it before another command or the next train simulation tick. */
	UpdateSignalsInBuffer();
	StringID error = cost.GetErrorMessage();
	_showcase_log += std::string(action) + (cost.Succeeded() ? "=ok\n" : "=failed: " + (error == INVALID_STRING_ID ? std::string("command rejected without a message") : GetString(error)) + "\n");
	return cost.Succeeded();
}

bool ModernBuildShowcase(bool world_gallery, bool city_gallery)
{
	/* Never alter an existing transport network or a multiplayer world. */
	bool has_transport = false;
	for (const Vehicle *vehicle : Vehicle::Iterate()) if (vehicle->type <= VehicleType::Aircraft) has_transport = true;
	if (_networking || has_transport || Map::SizeX() < (city_gallery ? 128 : 64) || Map::SizeY() < (city_gallery ? 128 : 64)) {
		_showcase_log = "fixture=requires a fresh offline world at least 64x64\n";
		return false;
	}
	Company *company = Company::GetIfValid(_local_company);
	if (company == nullptr) {
		company = DoStartupNewCompany(false, CompanyID::Invalid());
		if (company == nullptr) return false;
		SetLocalCompany(company->index, true);
	}
	AutoRestoreBackup current_company(_current_company, company->index);
	company->money = 5000000;
	AutoRestoreBackup terraform_limit(company->terraform_limit, UINT32_MAX);
	AutoRestoreBackup clear_limit(company->clear_limit, UINT32_MAX);
	DoCommandFlags flags{DoCommandFlag::Execute, DoCommandFlag::Auto};
	/* Prepare a level corridor before founding the two catchment towns. */
	auto [level, money, tile] = Command<Commands::LevelLand>::Do(flags, TileXY(61, 43), TileXY(14, 30), false, LevelMode::Level);
	Check("level terrain", level);
	for (auto [x, name] : {std::pair{18u, "Willowbridge"}, std::pair{54u, "Oakmere"}}) {
		AutoRestoreBackup deity(_current_company, CompanyID{OWNER_DEITY.base()});
		auto [result, town_cost, town] = Command<Commands::FoundTown>::Do(DoCommandFlag::Execute, TileXY(x, 35), TownSize::Medium, false, TownLayout::Grid2x2, false, x * 731, name);
		Check(name, result);
		if (result.Succeeded()) Command<Commands::TownRating>::Do(DoCommandFlag::Execute, town, company->index, 1000);
	}
	for (uint x = 17; x <= 60; ++x) Command<Commands::LandscapeClear>::Do(DoCommandFlag::Execute, TileXY(x, 40));
	for (Town *town : Town::Iterate()) town->ratings[company->index] = 1000;
	if (!Check("station west", Command<Commands::BuildRailStation>::Do(flags, TileXY(18,40), RAILTYPE_RAIL, Axis::X, 1, 4, STAT_CLASS_DFLT, 0, StationID::Invalid(), false))) return false;
	if (!Check("station east", Command<Commands::BuildRailStation>::Do(flags, TileXY(54,40), RAILTYPE_RAIL, Axis::X, 1, 4, STAT_CLASS_DFLT, 0, StationID::Invalid(), false))) return false;
	for (uint x = 22; x <= 53; ++x) if (!Check(fmt::format("rail {}", x), Command<Commands::BuildRail>::Do(flags, TileXY(x,40), RAILTYPE_RAIL, Track::X, false))) return false;
	if (!Check("depot approach", Command<Commands::BuildRail>::Do(flags, TileXY(58,40), RAILTYPE_RAIL, Track::X, false))) return false;
	if (!Check("depot", Command<Commands::BuildRailDepot>::Do(flags, TileXY(59,40), RAILTYPE_RAIL, DiagDirection::NE))) return false;
	auto [built, vehicle, capacity, mail, cargo] = Command<Commands::BuildVehicle>::Do(flags, TileXY(59,40), EngineID{22}, false, INVALID_CARGO, ClientID::Invalid);
	if (!Check("express locomotive", built)) return false;
	_showcase_train = vehicle;
	for (uint i = 0; i < 3; ++i) {
		auto [wagon, wagon_id, wc, wm, ca] = Command<Commands::BuildVehicle>::Do(flags, TileXY(59,40), EngineID{27}, false, INVALID_CARGO, ClientID::Invalid);
		if (!Check("passenger carriage", wagon)) return false;
		if (!Check("attach carriage", Command<Commands::MoveRailVehicle>::Do(flags, wagon_id, vehicle, false))) return false;
	}
	Order west, east;
	west.MakeGoToStation(GetStationIndex(TileXY(18,40)));
	east.MakeGoToStation(GetStationIndex(TileXY(54,40)));
	if (!Check("order west", Command<Commands::InsertOrder>::Do(flags, vehicle, VehicleOrderID{0}, west))) return false;
	if (!Check("order east", Command<Commands::InsertOrder>::Do(flags, vehicle, VehicleOrderID{1}, east))) return false;
	if (!Check("start express", Command<Commands::StartStopVehicle>::Do(flags, vehicle, true))) return false;
	if (world_gallery) {
		/* Explicit art fixture: both station axes, each default tile style and
		 * every engine terrain slope. Never runs in ordinary games. */
		for (auto axis : {Axis::X, Axis::Y}) {
			uint x = axis == Axis::X ? 31 : 40, y = axis == Axis::X ? 46 : 44;
			for (uint dx = 0; dx < 4; ++dx) for (uint dy = 0; dy < 4; ++dy) {
				Command<Commands::LandscapeClear>::Do(DoCommandFlag::Execute, TileXY(x+dx,y+dy));
			}
			for (Town *town : Town::Iterate()) town->ratings[company->index] = 1000;
			if (!Check(axis == Axis::X ? "gallery station X" : "gallery station Y", Command<Commands::BuildRailStation>::Do(flags, TileXY(x,y), RAILTYPE_RAIL, axis, 2, 4, STAT_CLASS_DFLT, 0, StationID::Invalid(), false))) return false;
			for (uint along = 0; along < 4; ++along) for (uint across = 0; across < 2; ++across) {
				auto tile = TileXY(x+(axis == Axis::X ? along : across),y+(axis == Axis::X ? across : along));
				SetStationGfx(tile, along*2+(axis == Axis::Y ? 1 : 0));
				SetRailStationTileFlags(tile, nullptr);
				MarkTileDirtyByTile(tile);
			}
		}
		const std::array<Slope, 19> slopes = {SLOPE_FLAT,SLOPE_W,SLOPE_S,SLOPE_SW,SLOPE_E,SLOPE_EW,SLOPE_SE,SLOPE_WSE,SLOPE_N,SLOPE_NW,SLOPE_NS,SLOPE_NWS,SLOPE_NE,SLOPE_ENW,SLOPE_SEN,SLOPE_STEEP_N,SLOPE_STEEP_S,SLOPE_STEEP_W,SLOPE_STEEP_E};
		for (uint i = 1; i < slopes.size(); ++i) {
			auto tile = TileXY(28+(i%5)*4,53+(i/5)*4);
			auto [result,cost,affected] = Command<Commands::TerraformLand>::Do(flags,tile,static_cast<Slope>(slopes[i]&15),true);
			if (!Check(fmt::format("gallery slope {}", i),result)) return false;
			if ((slopes[i]&SLOPE_STEEP) != 0) {
				Slope peak = slopes[i] == SLOPE_STEEP_N ? SLOPE_N : slopes[i] == SLOPE_STEEP_S ? SLOPE_S : slopes[i] == SLOPE_STEEP_W ? SLOPE_W : SLOPE_E;
				auto [raised,extra_cost,extra_tile] = Command<Commands::TerraformLand>::Do(flags,tile,peak,true);
				if (!Check(fmt::format("gallery steep peak {}", i),raised)) return false;
			}
			auto actual_slope = GetTileSlope(tile);
			_showcase_log += fmt::format("slope_{}_matches={}\n", i,actual_slope == slopes[i]);
		}
	}
	if (city_gallery) {
		ScrollMainWindowToTile(TileXY(40,56), true);
		AutoRestoreBackup house_rules(_settings_game.economy.place_houses, PlaceHouses::AllowedConstructed);
		for (uint line = 0; line <= 6; ++line) {
			if (!Check("city street X", Command<Commands::BuildRoadLong>::Do(flags,TileXY(49,51+line*3),TileXY(31,51+line*3),ROADTYPE_ROAD,Axis::X,{},false,false,false))) return false;
			if (!Check("city street Y", Command<Commands::BuildRoadLong>::Do(flags,TileXY(31+line*3,69),TileXY(31+line*3,51),ROADTYPE_ROAD,Axis::Y,{},false,false,false))) return false;
		}
		uint placed = 0;
		for (HouseID id = 0; id < NEW_HOUSE_OFFSET; ++id) {
			const HouseSpec *spec = HouseSpec::Get(id);
			if (!spec->enabled || !spec->building_availability.Test(HouseZone::ClimateTemperate)) continue;
			auto tile = TileXY(32+(placed%6)*3,52+(placed/6)*3);
			AutoRestoreBackup deity(_current_company, CompanyID{OWNER_DEITY.base()});
			if (!Check(fmt::format("city house {}",id),Command<Commands::PlaceHouse>::Do(DoCommandFlag::Execute,tile,id,false,false))) return false;
			++placed;
		}
		_showcase_log += fmt::format("city_house_types={}\n",placed);
		for (uint x = 31; x <= 49; ++x) for (uint y = 51; y <= 69; ++y) {
			auto tile = TileXY(x,y);
			if (IsNormalRoadTile(tile)) { SetRoadside(tile,Roadside::StreetLights); MarkTileDirtyByTile(tile); }
		}
		for (uint8_t bits = 1; bits < 16; ++bits) {
			auto tile = TileXY(54+((bits-1)%5)*3,51+((bits-1)/5)*3);
			if (!Check(fmt::format("road mask {}",bits),Command<Commands::BuildRoad>::Do(flags,tile,RoadBits{bits},ROADTYPE_ROAD,{},TownID::Invalid()))) return false;
			SetRoadside(tile,Roadside::Paved); MarkTileDirtyByTile(tile);
			_showcase_log += fmt::format("road_{}_matches={}\n",bits,GetRoadBits(tile,RoadTramType::Road).base()==bits);
		}
		if (!Check("city bus depot",Command<Commands::BuildRoadDepot>::Do(flags,TileXY(30,63),ROADTYPE_ROAD,DiagDirection::SW))) return false;
		if (!GetRoadBits(TileXY(31,63),RoadTramType::Road).Test(RoadBit::NE)) {
			if (!Check("city depot connection",Command<Commands::BuildRoad>::Do(flags,TileXY(31,63),RoadBit::NE,ROADTYPE_ROAD,{},TownID::Invalid()))) return false;
		}
		for (auto tile : {TileXY(31,55),TileXY(49,67)}) {
			if (!Check("city bus stop",Command<Commands::BuildRoadStop>::Do(flags,tile,1,1,RoadStopType::Bus,true,DiagDirection::SE,ROADTYPE_ROAD,RoadStopClassID{0},0,StationID::Invalid(),false))) return false;
		}
		EngineID bus_engine = EngineID::Invalid();
		for (const Engine *engine : Engine::Iterate()) {
			if (engine->type != VehicleType::Road) continue;
			CargoType cargo = engine->GetDefaultCargoType();
			if (!IsValidCargoType(cargo) || CargoSpec::Get(cargo)->label != CT_PASSENGERS) continue;
			bool available = IsEngineBuildable(engine->index,VehicleType::Road,company->index);
			_showcase_log += fmt::format("passenger_engine_{}_available={}\n",engine->index.base(),available);
			if (available) bus_engine = engine->index;
		}
		_showcase_log += fmt::format("bus_engine={}\n",bus_engine.base());
		if (bus_engine == EngineID::Invalid()) return false;
		auto [bus_cost,bus,bus_capacity,bus_mail,bus_cargo] = Command<Commands::BuildVehicle>::Do(flags,TileXY(30,63),bus_engine,false,INVALID_CARGO,ClientID::Invalid);
		if (!Check("city bus",bus_cost)) return false;
		uint order_index = 0;
		for (auto tile : {TileXY(31,55),TileXY(49,67)}) {
			Order order; order.MakeGoToStation(GetStationIndex(tile));
			order.SetStopLocation(OrderStopLocation::FarEnd);
			if (!Check("city bus order",Command<Commands::InsertOrder>::Do(flags,bus,static_cast<VehicleOrderID>(order_index++),order))) return false;
		}
		if (!Check("start city bus",Command<Commands::StartStopVehicle>::Do(flags,bus,true))) return false;
		_showcase_log += fmt::format("bus_id={}\n",bus.base());
	}
	ScrollMainWindowToTile(city_gallery ? TileXY(40,56) : world_gallery ? TileXY(37,48) : TileXY(40,39), true);
	_showcase_ok = true;
	return true;
}

void ModernSaveShowcaseReport(const std::string &stem)
{
	std::ofstream report(stem + ".showcase-check.txt");
	report << _showcase_log << "fixture_built=" << _showcase_ok << "\n";
	if (const Vehicle *train = Vehicle::GetIfValid(_showcase_train); train != nullptr) {
		report << "train_id=" << train->index.base() << "\nspeed=" << train->cur_speed << "\norders=" << uint(train->GetNumOrders()) << "\nprofit_this_year=" << train->GetDisplayProfitThisYear() << "\nposition=" << train->x_pos << "," << train->y_pos << "\n";
	}
	if (_showcase_ok) {
		auto saved = SaveOrLoad(stem + ".sav", SaveLoadOperation::Save, DetailedFileType::GameFile, Subdirectory::Save, false);
		report << "save_ok=" << (saved == SaveLoadResult::Ok) << "\n";
	}
}

void ModernInspectScene(const std::string &stem)
{
	std::ofstream report(stem + ".scene-check.txt");
	uint trains = 0;
	for (const Vehicle *train : Vehicle::Iterate()) {
		if (train->type != VehicleType::Train || !train->IsPrimaryVehicle()) continue;
		++trains;
		report << "train_id=" << train->index.base() << "\nspeed=" << train->cur_speed << "\norders=" << uint(train->GetNumOrders()) << "\nprofit_this_year=" << train->GetDisplayProfitThisYear() << "\nposition=" << train->x_pos << "," << train->y_pos << "\n";
	}
	report << "trains=" << trains << "\n";
	uint buses = 0;
	for (const Vehicle *bus : Vehicle::Iterate()) {
		if (bus->type != VehicleType::Road || !bus->IsPrimaryVehicle()) continue;
		++buses;
		report << "road_vehicle_id=" << bus->index.base() << "\nroad_speed=" << bus->cur_speed << "\nroad_orders=" << uint(bus->GetNumOrders()) << "\nroad_profit=" << bus->GetDisplayProfitThisYear() << "\nroad_position=" << bus->x_pos << "," << bus->y_pos << "\nroad_last_station=" << bus->last_station_visited.base() << "\n";
	}
	report << "road_vehicles=" << buses << "\n";
}
