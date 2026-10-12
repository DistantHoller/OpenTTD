/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file osx_main.cpp Main entry for Mac OS X. */

#include "../../stdafx.h"
#include "../../openttd.h"
#include "../../crashlog.h"
#include "../../core/random_func.hpp"
#include "../../string_func.h"

#include <time.h>
#include <signal.h>

#include "macos.h"

#include "../../safeguards.h"

void CocoaSetupAutoreleasePool();
void CocoaReleaseAutoreleasePool();
#ifdef MODERN_EDITION
std::string PrepareModernProfile();
#endif

int CDECL main(int argc, char *argv[])
{
	/* Make sure our arguments contain only valid UTF-8 characters. */
	std::vector<std::string_view> params;
	for (int i = 0; i < argc; ++i) {
		StrMakeValidInPlace(argv[i]);
		params.emplace_back(argv[i]);
	}

	CocoaSetupAutoreleasePool();
	/* This is passed if we are launched by double-clicking */
	if (params.size() >= 2 && params[1].starts_with("-psn")) {
		params.resize(1);
	}

#ifdef MODERN_EDITION
	std::string profile;
	bool explicit_config = std::find(params.begin(), params.end(), "-c") != params.end();
	bool help = std::find(params.begin(), params.end(), "-h") != params.end();
	if (!explicit_config && !help) {
		profile = PrepareModernProfile();
		if (!profile.empty()) { params.emplace_back("-c"); params.emplace_back(profile); }
	}
#endif

	CrashLog::InitialiseCrashLog();

	SetRandomSeed(time(nullptr));

	signal(SIGPIPE, SIG_IGN);

	int ret = openttd_main(params);

	CocoaReleaseAutoreleasePool();

	return ret;
}
