//
//  PluginList.m
//  Pcsxr
//
//  Created by Gil Pedersen on Sun Sep 21 2003.
//  Copyright (c) 2003 __MyCompanyName__. All rights reserved.
//

#import "EmuThread.h"
#import "PluginList.h"
#import "PcsxrPlugin.h"
#include "psxcommon.h"
#include "plugins.h"

//NSMutableArray *plugins;
static PluginList *sPluginList = nil;
const static int typeList[5] = {PSE_LT_GPU, PSE_LT_SPU, PSE_LT_CDR, PSE_LT_PAD, PSE_LT_NET};

@implementation PluginList

+ (PluginList *)list
{
	return sPluginList;
}

#if 0
+ (void)loadPlugins
{
    NSDirectoryEnumerator *dirEnum;
    NSString *pname, *dir;
    
    // Make sure we only load the plugins once
    if (plugins != nil)
        return;
    
    plugins = [[NSMutableArray alloc] initWithCapacity: 20];

    dir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:Config.PluginsDir length:strlen(Config.PluginsDir)];
    dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    
    while (pname = [dirEnum nextObject]) {
        if ([[pname pathExtension] isEqualToString:@"psxplugin"] || 
            [[pname pathExtension] isEqualToString:@"so"]) {
            [dirEnum skipDescendents]; /* don't enumerate this
                                            directory */
            
            PcsxrPlugin *plugin = [[PcsxrPlugin alloc] initWithPath:pname];
            if (plugin != nil) {
                [plugins addObject:plugin];
            }
        }
    }
}

- (id)initWithType:(int)typeMask
{
    unsigned int i;
    
    self = [super init];

    [PluginList loadPlugins];
    list = [[NSMutableArray alloc] initWithCapacity: 5];
    
    type = typeMask;
    for (i=0; i<[plugins count]; i++) {
        PcsxrPlugin *plugin = [plugins objectAtIndex:i];
        if ([plugin type] == type) {
            [list addObject:plugin];
        }
    }
    
    return self;
}

- (int)numberOfItems
{
    return [list count];
}

- (id)objectAtIndex:(unsigned)index
{
	return [list objectAtIndex:index];
}
#endif



- (id)init
{
	NSUInteger i;
	
	if (!(self = [super init]))
	{
		[self autorelease];
		return nil;
	}
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	pluginList = [[NSMutableArray alloc] initWithCapacity:20];

	activeGpuPlugin = activeSpuPlugin = activeCdrPlugin = activePadPlugin = activeNetPlugin = nil;
	
	missingPlugins = NO;
	for (i = 0; i < sizeof(*typeList); i++) {
		NSString *path = [defaults stringForKey:[PcsxrPlugin defaultKeyForType:typeList[i]]];
		if (nil == path) {
			missingPlugins = YES;
			continue;
		}
		if ([path isEqualToString:@"Disabled"])
			continue;
		
		if (![self hasPluginAtPath:path]) {
			PcsxrPlugin *plugin = [[PcsxrPlugin alloc] initWithPath:path];
			if (plugin) {
				[pluginList addObject:plugin];
				if (![self setActivePlugin:plugin forType:typeList[i]])
					missingPlugins = YES;
			} else {
				missingPlugins = YES;
			}
		}
	}
	
	if (missingPlugins) {
		[self refreshPlugins];
	}
	
	sPluginList = self;
	
	return self;
}

- (void)dealloc
{
	[activeGpuPlugin release];
	[activeSpuPlugin release];
	[activeCdrPlugin release];
	[activePadPlugin release];
	[activeNetPlugin release];
	
	[pluginList release];
	
	if (sPluginList == self)
		sPluginList = nil;
	
	[super dealloc];
}

- (void)refreshPlugins
{
	NSDirectoryEnumerator *dirEnum;
	NSString *pname, *dir;
	NSUInteger i;
	
	// verify that the ones that are in list still works
	for (i=0; i<[pluginList count]; i++) {
		if (![[pluginList objectAtIndex:i] verifyOK]) {
			[pluginList removeObjectAtIndex:i]; i--;
		}
	}
	
	// look for new ones in the plugin directory
	dir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:Config.PluginsDir length:strlen(Config.PluginsDir)];
	dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:dir];
	
	while ((pname = [dirEnum nextObject])) {
		if ([[pname pathExtension] isEqualToString:@"psxplugin"] || 
			[[pname pathExtension] isEqualToString:@"so"]) {
			[dirEnum skipDescendents]; /* don't enumerate this
														directory */
			
			if (![self hasPluginAtPath:pname]) {
				PcsxrPlugin *plugin = [[PcsxrPlugin alloc] initWithPath:pname];
				if (plugin != nil) {
					[pluginList addObject:plugin];
				}
			}
		}
	}
	
	// check the we have the needed plugins
	missingPlugins = NO;
	for (i=0; i<sizeof(*typeList); i++) {
		PcsxrPlugin *plugin = [self activePluginForType:typeList[i]];
		if (nil == plugin) {
			NSArray *list = [self pluginsForType:typeList[i]];
			NSUInteger j;
			
			for (j=0; j<[list count]; j++) {
				if ([self setActivePlugin:[list objectAtIndex:j] forType:typeList[i]])
					break;
			}
			if (j == [list count])
				missingPlugins = YES;
		}
	}
}

- (NSArray *)pluginsForType:(int)typeMask
{
	NSMutableArray *types = [NSMutableArray array];
	NSUInteger i;
	
	for (i=0; i<[pluginList count]; i++) {
		PcsxrPlugin *plugin = [pluginList objectAtIndex:i];
		
		if ([plugin type] & typeMask) {
			[types addObject:plugin];
		}
	}
	
	return types;
}

- (BOOL)hasPluginAtPath:(NSString *)path
{
	if (nil == path)
		return NO;
	
	NSUInteger i;
	for (i=0; i<[pluginList count]; i++) {
		if ([[[pluginList objectAtIndex:i] path] isEqualToString:path])
			return YES;
	}
	
	return NO;
}

// returns if all the required plugins are available
- (BOOL)configured
{
	return !missingPlugins;
}

- (BOOL)doInitPlugins
{
	BOOL bad = NO;
	
	if ([activeGpuPlugin initAs:PSE_LT_GPU] != 0) bad = YES;
	if ([activeSpuPlugin initAs:PSE_LT_SPU] != 0) bad = YES;
	if ([activeCdrPlugin initAs:PSE_LT_CDR] != 0) bad = YES;
	if ([activePadPlugin initAs:PSE_LT_PAD] != 0) bad = YES;
	if ([activeNetPlugin initAs:PSE_LT_NET] != 0) bad = YES;
	
	return !bad;
}

- (PcsxrPlugin *)activePluginForType:(int)type
{
	switch (type) {
		case PSE_LT_GPU: return activeGpuPlugin;
		case PSE_LT_CDR: return activeCdrPlugin;
		case PSE_LT_SPU: return activeSpuPlugin;
		case PSE_LT_PAD: return activePadPlugin;
		case PSE_LT_NET: return activeNetPlugin;
	}
	
	return nil;
}

- (BOOL)setActivePlugin:(PcsxrPlugin *)plugin forType:(int)type
{
	PcsxrPlugin **pluginPtr;
	switch (type) {
		case PSE_LT_GPU: pluginPtr = &activeGpuPlugin; break;
		case PSE_LT_CDR: pluginPtr = &activeCdrPlugin; break;
		case PSE_LT_SPU: pluginPtr = &activeSpuPlugin; break;
		case PSE_LT_PAD: pluginPtr = &activePadPlugin; break;
		case PSE_LT_NET: pluginPtr = &activeNetPlugin; break;
		default: return NO;
	}
	
	if (plugin == *pluginPtr)
		return YES;
	
	BOOL active = (*pluginPtr) && [EmuThread active];
	BOOL wasPaused = NO;
	if (active) {
		// TODO: temporary freeze?
		wasPaused = [EmuThread pauseSafe];
		ClosePlugins();
		ReleasePlugins();
	}
	
	// stop the old plugin and start the new one
	if (*pluginPtr) {
		[*pluginPtr shutdownAs:type];
		
		[*pluginPtr release];
	}
	*pluginPtr = [plugin retain];
	if (*pluginPtr) {
		if ([*pluginPtr initAs:type] != 0) {
			[*pluginPtr release];
			*pluginPtr = nil;
		}
	}
	
	// write path to the correct config entry
	const char *str;
	if (*pluginPtr != nil) {
		str = [[plugin path] fileSystemRepresentation];
		if (str == nil) {
			str = "Invalid Plugin";
		}
	} else {
		str = "Invalid Plugin";
	}
	
	char **dst = [PcsxrPlugin configEntriesForType:type];
	while (*dst) {
		strncpy(*dst, str, MAXPATHLEN);
		dst++;
	}
	
	if (active) {
		LoadPlugins();
		OpenPlugins();
		
		if (!wasPaused) {
			[EmuThread resume];
		}
	}
	
	return *pluginPtr != nil;
}

@end
