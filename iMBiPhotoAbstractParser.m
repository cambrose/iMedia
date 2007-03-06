/*
 
 Permission is hereby granted, free of charge, to any person obtaining a 
 copy of this software and associated documentation files (the "Software"), 
 to deal in the Software without restriction, including without limitation 
 the rights to use, copy, modify, merge, publish, distribute, sublicense, 
 and/or sell copies of the Software, and to permit persons to whom the Software 
 is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in 
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS 
 FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR 
 COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
 AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION 
 WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 iMedia Browser Home Page: <http://imedia.karelia.com/>
 
 Please send fixes to <imedia@lists.karelia.com>

*/

#import "iMBiPhotoAbstractParser.h"
#import "iMediaBrowser.h"
#import "iMBLibraryNode.h"
#import "iMedia.h"

@implementation iMBiPhotoAbstractParser

- (id)init
{
	if (self = [super initWithContentsOfFile:nil])
	{
		CFPropertyListRef iApps = CFPreferencesCopyAppValue((CFStringRef)@"iPhotoRecentDatabases",
															(CFStringRef)@"com.apple.iApps");
		
		NSArray *libraries = (NSArray *)iApps;
		NSEnumerator *e = [libraries objectEnumerator];
		NSString *cur;
		
		while (cur = [e nextObject]) {
			[self watchFile:cur];
		}
		[libraries autorelease];
	}
	return self;
}

- (NSString *)iconNameForType:(NSString*)name
{
	if ([name isEqualToString:@"Special Roll"])
		return @"MBiPhotoRoll";
	else if ([name hasSuffix:@"Rolls"])
		return @"MBiPhotoRoll";
	else if ([name isEqualToString:@"Special Month"])
		return @"MBiPhotoCalendar";
	else if ([name hasSuffix:@"Months"])
		return @"MBiPhotoCalendar";
	else if ([name isEqualToString:@"Subscribed"])
		return @"photocast";
	else if ([name isEqualToString:@"Photocasts"])
		return @"photocast_folder";
	else if ([name isEqualToString:@"Slideshow"])
		return @"slideshow";
	else if ([name isEqualToString:@"Book"])
		return @"book";
	else if ([name isEqualToString:@"Calendar"])
		return @"calendar";
	else if ([name isEqualToString:@"Card"])
		return @"card";
	else if (name == nil)
		return @"com.apple.iPhoto";			// top level library
	else
		return @"MBiPhotoAlbum";
}

- (iMBLibraryNode *)nodeWithAlbumID:(NSNumber *)aid withRoot:(iMBLibraryNode *)root
{
	if ([[root attributeForKey:@"AlbumId"] longValue] == [aid longValue])
	{
		return root;
	}
	NSEnumerator *e = [[root items] objectEnumerator];
	iMBLibraryNode *cur;
	iMBLibraryNode *found;
	
	while (cur = [e nextObject])
	{
		found = [self nodeWithAlbumID:[[aid retain] autorelease] withRoot:cur];
		if (found)
		{
			return found;
		}
	}
	return nil;
}

// General parser

- (iMBLibraryNode *)parseDatabaseAttributeKey:(NSString *)anImagePath
								 mediaType:(NSString *)aMediaType
							   wantUntyped:(BOOL)aWantUntyped
							 wantThumbPath:(BOOL)aWantThumbPath
{
	iMBLibraryNode *root = [[[iMBLibraryNode alloc] init] autorelease];
	[root setName:LocalizedStringInThisBundle(@"iPhoto", @"iPhoto")];
	[root setIconName:@"photo_tiny"];
	[root setFilterDuplicateKey:@"ImagePath" forAttributeKey:anImagePath];
	
	NSMutableDictionary *library = [NSMutableDictionary dictionary];
	
	//Find all iPhoto libraries
	CFPropertyListRef iApps = CFPreferencesCopyAppValue((CFStringRef)@"iPhotoRecentDatabases",
														(CFStringRef)@"com.apple.iApps");
	
	//Iterate over libraries, pulling dictionary from contents and adding to array for processing;
	NSArray *libraries = (NSArray *)iApps;
	NSEnumerator *e = [libraries objectEnumerator];
	NSString *cur;
	
	while (cur = [e nextObject]) {
		NSDictionary *db = [NSDictionary dictionaryWithContentsOfURL:[NSURL URLWithString:cur]];
		if (db) {
			[library addEntriesFromDictionary:db];
		}
	}
	[libraries autorelease];
	
	if ([[library allKeys] count] == 0)
	{
		return nil;
	}
	
	NSDictionary *imageRecords = [library objectForKey:@"Master Image List"];
	NSDictionary *keywordMap = [library objectForKey:@"List of Keywords"];
	NSEnumerator *albumEnum = [[library objectForKey:@"List of Albums"] objectEnumerator];
	NSDictionary *albumRec;
	int fakeAlbumID = 0;
	
	//Parse dictionary creating libraries, and filling with track infromation
	while (albumRec = [albumEnum nextObject])
	{
		if ([[albumRec objectForKey:@"Album Type"] isEqualToString:@"Book"] ||
			[[albumRec objectForKey:@"Album Type"] isEqualToString:@"Slideshow"])
		{
			continue;
		}

		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

		iMBLibraryNode *lib = [[[iMBLibraryNode alloc] init] autorelease];
		[lib setName:[albumRec objectForKey:@"AlbumName"]];
		[lib setIconName:[self iconNameForType:[albumRec objectForKey:@"Album Type"]]];
		// iPhoto 2 doesn't have albumID's so let's just fake them
		NSNumber *aid = [albumRec objectForKey:@"AlbumId"];
		if (!aid)
		{
			aid = [NSNumber numberWithInt:fakeAlbumID];
			fakeAlbumID++;
		}
		[lib setAttribute:aid forKey:@"AlbumId"];
		
		NSMutableArray *newPhotolist = [NSMutableArray array];
		NSEnumerator *pictureItemsEnum = [[albumRec objectForKey:@"KeyList"] objectEnumerator];
		NSString *key;
		BOOL hasItems = NO;

		while (key = [pictureItemsEnum nextObject])
		{
			NSMutableDictionary *imageRecord = [[[imageRecords objectForKey:key] mutableCopy] autorelease];
			NSString *mediaType = [imageRecord objectForKey:@"MediaType"];
			if (!aWantUntyped && !mediaType)
			{
				continue;	// skip if media type is missing and we require a media type
			}
			if (mediaType && ![mediaType isEqualToString:aMediaType])
			{
				continue;	// skip if this media type doesn't match what we are looking for
			}
			hasItems = YES;
			if (aWantThumbPath)
			{
				[imageRecord setObject:[imageRecord objectForKey:@"ThumbPath"] forKey:@"Preview"];
			}
				
			[newPhotolist addObject:imageRecord];
			//swap the keyword index to names
			NSArray *keywords = [imageRecord objectForKey:@"Keywords"];
			if ([keywords count] > 0) {
				NSEnumerator *keywordEnum = [keywords objectEnumerator];
				NSString *keywordKey;
				NSMutableArray *realKeywords = [NSMutableArray array];
				
				while (keywordKey = [keywordEnum nextObject]) {
					NSString *actualKeyword = [keywordMap objectForKey:keywordKey];
					if (actualKeyword)
					{
						[realKeywords addObject:actualKeyword];
					}
				}
				
				[imageRecord setObject:realKeywords forKey:@"iMediaKeywords"];
			}
		}
		[lib setAttribute:newPhotolist forKey:anImagePath];
		
		if (hasItems) // only display albums that have movies.... what happens when a child album has items we want, but the parent doesn't?
		{

			if ([albumRec objectForKey:@"Parent"])
			{
				iMBLibraryNode *parent = [self nodeWithAlbumID:[albumRec objectForKey:@"Parent"]
													  withRoot:root];
				if (!parent)
					NSLog(@"Failed to find parent node");
				[parent addItem:lib];
			}
			else
			{
				[root addItem:lib];
			}
		}		
		[pool release];
	}

	if ([[root valueForKey:anImagePath] count] == 0)
	{
		root = nil;
	}
	
	return root;
}

@end