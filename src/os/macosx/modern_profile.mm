/* Independent first-run profile, added 2026-10-12. SPDX-License-Identifier: GPL-2.0-only */
#include "../../stdafx.h"
#import <Foundation/Foundation.h>

std::string PrepareModernProfile()
{
	@autoreleasepool {
		NSBundle *bundle = NSBundle.mainBundle;
		NSString *defaults = [bundle.resourcePath stringByAppendingPathComponent:@"modern-defaults.cfg"];
		NSFileManager *files = NSFileManager.defaultManager;
		/* A direct development binary has no bundled defaults. */
		if (![files fileExistsAtPath:defaults]) return {};
		NSURL *support = [files URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
		NSURL *directory = [support URLByAppendingPathComponent:@"OpenTTD Modern" isDirectory:YES];
		NSError *error = nil;
		if (![files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
			fprintf(stderr, "Cannot create OpenTTD profile: %s\n", error.localizedDescription.UTF8String); return {};
		}
		NSURL *config = [directory URLByAppendingPathComponent:@"openttd.cfg"];
		if (![files fileExistsAtPath:config.path] && ![files copyItemAtPath:defaults toPath:config.path error:&error]) {
			fprintf(stderr, "Cannot create OpenTTD settings: %s\n", error.localizedDescription.UTF8String); return {};
		}
		return config.path.fileSystemRepresentation;
	}
}
