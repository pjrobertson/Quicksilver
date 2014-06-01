//
// QSHandledObjectHandler.m
// Quicksilver
//
// Created by Nicholas Jitkoff on 9/24/05.
// Copyright 2005 __MyCompanyName__. All rights reserved.
//

#import "QSHandledObjectHandler.h"

#import "QSRegistry.h"
#import "QSObject.h"
#import "QSAction.h"
#import "QSTypes.h"
#import "QSResourceManager.h"

@implementation QSInternalObjectSource
- (BOOL)entryCanBeIndexed:(NSDictionary *)theEntry {return NO;}

- (BOOL)indexIsValidFromDate:(NSDate *)indexDate forEntry:(NSDictionary *)theEntry { return YES; }
- (NSImage *)iconForEntry:(NSDictionary *)dict { return [QSResourceManager imageNamed:@"Object"]; }
- (NSArray *)objectsForEntry:(NSDictionary *)theEntry {
	NSDictionary *messages = [QSReg tableNamed:@"QSInternalObjects"];
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[messages count]];
	QSObject *messageObject;
	NSDictionary *info;
	for (NSString *key in messages) {
		info = [messages objectForKey:key];
        NSDictionary *objDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSDictionary dictionaryWithObjectsAndKeys:
                                  [info objectForKey:@"name"], kQSObjectPrimaryName,
                                  [info objectForKey:@"icon"], kQSObjectIcon,
                                  key, kQSObjectObjectID,
                                  QSHandledType, kQSObjectPrimaryType,
                                  nil], kMeta,
                                 nil];
		messageObject = [QSObject objectWithDictionary:objDict];
        if( messageObject != nil )
            [array addObject:messageObject];
	}
	return array;
}

@end
