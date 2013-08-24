//
//  PVDirectoryWatcher.m
//  Provenance
//
//  Created by James Addyman on 11/04/2013.
//  Copyright (c) 2013 Testut Tech. All rights reserved.
//

#import "PVDirectoryWatcher.h"
#import "ZKDataArchive.h"
#import "ZKDefs.h"

@interface PVDirectoryWatcher () {
	
	dispatch_source_t _dispatch_source;
	
}

@end

@implementation PVDirectoryWatcher

- (id)initWithPath:(NSString *)path directoryChangedHandler:(PVDirectoryChangedHandler)handler
{
	if ((self = [super init]))
	{
		_path = [path copy];
		
		BOOL isDirectory = NO;
		BOOL fileExists = [[NSFileManager defaultManager] fileExistsAtPath:_path
											 isDirectory:&isDirectory];
		if ((fileExists == NO) || (isDirectory == NO))
		{
			NSError *error = nil;
			BOOL succeeded = [[NSFileManager defaultManager] createDirectoryAtPath:_path
													   withIntermediateDirectories:YES
																		attributes:nil
																			 error:&error];
			if (!succeeded)
			{
				NSLog(@"Unable to create directory at: %@, because: %@", _path, [error localizedDescription]);
			}
		}
		
		_directoryChangedHandler = [handler copy];
	}
	
	return self;
}

- (void)dealloc
{
    _directoryChangedHandler = nil;
}

- (void)startMonitoring
{
	if (![self.path length])
	{
		return;
	}
	
	[self stopMonitoring];
	
	int dirFileDescriptor = open([self.path fileSystemRepresentation], O_EVTONLY);
	if (dirFileDescriptor < 0)
	{
		return;
	}
	
	_dispatch_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,
											  dirFileDescriptor,
											  DISPATCH_VNODE_WRITE |
											  DISPATCH_VNODE_DELETE |
											  DISPATCH_VNODE_RENAME,
											  dispatch_get_main_queue());
	if (!_dispatch_source)
	{
		return;
	}
	
	dispatch_source_set_event_handler(_dispatch_source, ^{
		[self performSelector:@selector(findAndExtractArchives) withObject:nil afterDelay:1.0];
	});
	
	dispatch_resume(_dispatch_source);
}

- (void)stopMonitoring
{
	if (_dispatch_source)
	{
		_directoryChangedHandler = NULL;
		_path = nil;
		dispatch_source_cancel(_dispatch_source);
		_dispatch_source = NULL;
	}
}

- (void)findAndExtractArchives
{
	dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSFileManager *fileManager = [NSFileManager defaultManager];
		NSArray *contents = [fileManager contentsOfDirectoryAtPath:self.path error:NULL];
		
		for (NSString *path in contents)
		{
			NSString *filePath = [self.path stringByAppendingPathComponent:path];
			BOOL isDir = NO;
			[fileManager fileExistsAtPath:filePath isDirectory:&isDir];
			if (isDir || ([ZKDataArchive validArchiveAtPath:filePath] == NO))
			{
				continue;
			}
			
			ZKDataArchive *archive = [ZKDataArchive archiveWithArchivePath:filePath];
			NSUInteger success = [archive inflateAll];
			if (success)
			{
				[fileManager removeItemAtPath:filePath error:NULL];
				
				for (NSDictionary *inflatedFile in [archive inflatedFiles])
				{
					NSString *fileName = [inflatedFile objectForKey:ZKPathKey];
					if ([fileName hasSuffix:@"smd"] || [fileName hasSuffix:@"SMD"] || [fileName hasSuffix:@"bin"] || [fileName hasSuffix:@"BIN"])
					{
						NSData *fileData = [inflatedFile objectForKey:ZKFileDataKey];
						[fileData writeToFile:[self.path stringByAppendingPathComponent:fileName] atomically:YES];
					}
				}
			}
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			if (self.directoryChangedHandler != NULL)
			{
				self.directoryChangedHandler();
			}
		});
	});
}

@end
