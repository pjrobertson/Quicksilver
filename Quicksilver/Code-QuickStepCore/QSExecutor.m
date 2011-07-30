#import "QSKeys.h"
#import "QSExecutor.h"
#import "QSLibrarian.h"
#import "QSObject.h"
#import "QSTypes.h"

#import "QSRankedObject.h"
#import "QSProxyObject.h"
#import "QSMacros.h"

#import "QSObjectSource.h"

#import "QSController.h"

#import "NSObject+ReaperExtensions.h"
#import "QSObject_FileHandling.h"
#import "QSObject_PropertyList.h"

#import "NSBundle_BLTRExtensions.h"
#import "QSTaskController.h"

#import "QSMnemonics.h"

#import "QSAction.h"
#import "QSActionProvider.h"
#import "QSResourceManager.h"

#import "QSRegistry.h"

#import "QSNullObject.h"
#import "NSException_TraceExtensions.h"

//#define compGT(a, b) (a < b)

#define pQSActionsLocation QSApplicationSupportSubPath(@"Actionsv2.plist", NO)
#define pQSOldActionsLocation QSApplicationSupportSubPath(@"Actions.plist", NO)


QSExecutor *QSExec = nil;

@interface QSObject (QSActionsHandlerProtocol)
- (NSArray *)actionsForDirectObject:(QSObject *)dObject indirectObject:(QSObject *)iObject;
@end

@interface QSAction (QSPrivate)
- (void)_setRank:(int)newRank;
@end

@implementation QSExecutor
+ (id)sharedInstance {
	if (!QSExec) QSExec = [[[self class] allocWithZone:[self zone]] init];
	return QSExec;
}

- (id)init {
	if (self = [super init]) {
		actionSources = [[NSMutableDictionary alloc] initWithCapacity:1];
		
		// The full list of actions, populated when QS starts up - by scanning all the plugins' .plists
		actionIdentifiers = [[NSMutableDictionary alloc] initWithCapacity:1];
		directObjectTypes = [[NSMutableDictionary alloc] initWithCapacity:1];
	 	directObjectFileTypes = [[NSMutableDictionary alloc] initWithCapacity:1];

		NSDictionary *actionsPrefs = [[NSDictionary alloc] initWithContentsOfFile:pQSActionsLocation];
		NSDictionary *oldActionsPrefs = nil;
		NSDictionary *actionActivation = nil;
		
		// Upgrading from an older QS version? New QS Installation?
		if (!actionsPrefs) {
			oldActionsPrefs = [[NSDictionary  alloc] initWithContentsOfFile:pQSOldActionsLocation];
			if (!oldActionsPrefs) {
				// New QS installation
				actionsPrefs = [NSDictionary dictionary];
			}
			else {
				// Upgrade the old school actions prefs
					NSLog(@"Creating / Upgrading the Actions .plist");
				actionsPrefs = [oldActionsPrefs copy];
					// Alter the format. We've moving from an NSDict with 'enabled' bool 
					// keys to 2 NSSets defining the enabled/disabled actions
				actionActivation = [actionsPrefs objectForKey:@"actionActivation"];
				NSMutableArray *tempEnabledActions = [[NSMutableArray alloc] init];
				NSMutableArray *tempDisabledActions = [[NSMutableArray alloc] init];
				for(NSString * key in actionActivation) {
						BOOL enabled = [[actionActivation objectForKey:key] boolValue];
						if (enabled == TRUE) {
							[tempEnabledActions addObject:key];
						}
						else {
							[tempDisabledActions addObject:key];
						}
					}
				enabledActions = [tempEnabledActions mutableCopy];
				disabledActions = [tempDisabledActions mutableCopy];
				[tempEnabledActions release];
				[tempDisabledActions release];
				actionActivation = [NSDictionary dictionaryWithObjects: [NSArray arrayWithObjects:enabledActions, disabledActions,nil] forKeys: [NSArray arrayWithObjects:@"enabledActions",@"disabledActions",nil] ];
			}
		}
		actionPrecedence = [[actionsPrefs objectForKey:@"actionPrecedence"] mutableCopy];
		actionRanking = [[actionsPrefs objectForKey:@"actionRanking"] mutableCopy];
		// Actions that appear in the 'actions menu' (use 'show action menu' action to see it)
		actionMenuActivation = [[actionsPrefs objectForKey:@"actionMenuActivation"] mutableCopy];
		
		
		// actionActivation: Actions that show up in the 2nd pane.
		// If we haven't gone through the upgrade process, we need to get this from the .plist
		if (!actionActivation) {
			actionActivation = [actionsPrefs objectForKey:@"actionActivation"];
			// set the enabled and disabled actions
			enabledActions = [[actionActivation objectForKey:@"enabledActions"] mutableCopy];
			disabledActions = [[actionActivation objectForKey:@"disabledActions"]mutableCopy];
		}
		
		actionIndirects = [[actionsPrefs objectForKey:@"actionIndirects"] mutableCopy];
		actionNames = [[actionsPrefs objectForKey:@"actionNames"] mutableCopy];
		
		[actionsPrefs release];

		if (!actionPrecedence)
			actionPrecedence = [[NSMutableDictionary alloc] init];
		if (!actionRanking)
			actionRanking = [[NSMutableArray alloc] init];
		if (!actionMenuActivation)
			actionMenuActivation = [[NSMutableDictionary alloc] init];
		if (!actionIndirects)
			actionIndirects = [[NSMutableDictionary alloc] init];
		if (!actionNames)
			actionNames = [[NSMutableDictionary alloc] init];
		
		
		if (oldActionsPrefs) {
			NSLog(@"Writing the new Actions preferences to Actionsv2.plist");
			[self writeActionsInfoNow];
			[oldActionsPrefs release];
		}
		//[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(writeCatalog:) name:QSCatalogEntryChanged object:nil];
#if 0
		[(NSImage *)[[[NSImage alloc] initWithSize:NSZeroSize] autorelease] setName:@"QSDirectProxyImage"];
		[(NSImage *)[[[NSImage alloc] initWithSize:NSZeroSize] autorelease] setName:@"QSDefaultAppProxyImage"];
		[(NSImage *)[[[NSImage alloc] initWithSize:NSZeroSize] autorelease] setName:@"QSIndirectProxyImage"];
#endif
	}
	return self;
}

- (void)dealloc {
	// [self writeCatalog:self];
	[actionIdentifiers release];
	[directObjectTypes release];
	[directObjectFileTypes release];
	[actionSources release];
	[actionRanking release];
	[actionPrecedence release];
	[enabledActions release];
	[disabledActions release];
	[actionMenuActivation release];
	[actionIndirects release];
	[actionNames release];	
	[super dealloc];
}

- (void)loadFileActions {
	NSString *rootPath = QSApplicationSupportSubPath(@"Actions/", NO);
	NSArray *files = [rootPath performSelector:@selector(stringByAppendingPathComponent:) onObjectsInArray:[[NSFileManager defaultManager] contentsOfDirectoryAtPath:rootPath error:nil]];
	for(id <QSFileActionProvider> creator in [[QSReg instancesForTable:@"QSFileActionCreators"] allValues]) {
		[self addActions:[creator fileActionsFromPaths:files]];
	}
}

- (NSArray *)actionsForFileTypes:(NSArray *)types {
	NSMutableSet *set = [NSMutableSet set];
	for (NSString *type in types) {
		[set addObjectsFromArray:[directObjectFileTypes objectForKey:type]];
	}
	[set addObjectsFromArray:[directObjectFileTypes objectForKey:@"*"]];
	return [set allObjects];
}

- (NSArray *)actionsForTypes:(NSArray *)types fileTypes:(NSArray *)fileTypes {
	NSMutableSet *set = [NSMutableSet set];
	for (NSString *type in types) {
		if ([type isEqualToString:QSFilePathType]) {
			[set addObjectsFromArray:[self actionsForFileTypes:fileTypes]];
		} else {
			[set addObjectsFromArray:[directObjectTypes objectForKey:type]];
		}
	}
	[set addObjectsFromArray:[directObjectTypes objectForKey:@"*"]];
	return [set allObjects];
}


- (NSMutableArray *)actionsArrayForType:(NSString *)type {
	NSMutableArray *array = [directObjectTypes objectForKey:type];
	if (!array)
		[directObjectTypes setObject:(array = [NSMutableArray array]) forKey:type];
	return array;
}

- (NSMutableArray *)actionsArrayForFileType:(NSString *)type {
	NSMutableArray *array = [directObjectFileTypes objectForKey:type];
	if (!array)
		[directObjectFileTypes setObject:(array = [NSMutableArray array]) forKey:type];
	return array;
}

- (void)addActions:(NSArray *)actions {
	for (QSAction * action in actions) {
		[self addAction:action];
	}
}

- (void)addAction:(QSAction *)action {
	NSString *ident = [action identifier];
	if (!ident)
		return;
	NSString *altName = [actionNames objectForKey:ident];
	if (altName) [action setLabel:altName];
	QSAction *dupAction = [actionIdentifiers objectForKey:ident];
	if (dupAction) {
		[[directObjectTypes allValues] makeObjectsPerformSelector:@selector(removeObject:) withObject:dupAction];
		[[directObjectFileTypes allValues] makeObjectsPerformSelector:@selector(removeObject:) withObject:dupAction];
	}
	
	[actionIdentifiers setObject:action forKey:ident];

	// If there are no user-defined action settings (enabled/disabled) for this action, set its enabled value
	// to be the default (defined by the 'enabled' BOOL in the Info.plist) ** The 'enabled' bool should really
	// be called 'enabledByDefault' or something similar
	if(![enabledActions containsObject:ident] && ![disabledActions containsObject:ident]) {
		[action setEnabled:[action defaultEnabled]];
	}
	

	// action menu actions
    
    BOOL activation = NO;
    NSNumber *act = [actionMenuActivation objectForKey:ident];
	if (act)
        activation = [act boolValue];
    else
        activation = [action defaultEnabled];
	[action setMenuEnabled:activation];    

	
		
	int index = [actionRanking indexOfObject:ident];

	if (index == NSNotFound) {
		float prec = [action precedence];
		int i;
		float otherPrec;
		for(i = 0; i < [actionRanking count]; i++) {
			otherPrec = [[actionPrecedence valueForKey:[actionRanking objectAtIndex:i]] floatValue];
			if (otherPrec < prec) break;
		}
		[actionRanking insertObject:ident atIndex:i];
		[actionPrecedence setObject:[NSNumber numberWithFloat:prec] forKey:ident];
		[action setRank:i];
#ifdef DEBUG
		if (VERBOSE) NSLog(@"inserting action %@ at %d (%f) ", action, i, prec);
#endif
	} else {
		[action _setRank:index];
	}
	if([action enabled]) {
	NSDictionary *actionDict = [action objectForType:QSActionType];
	NSArray *directTypes = [actionDict objectForKey:@"directTypes"];
	if (![directTypes count]) directTypes = [NSArray arrayWithObject:@"*"];
	for (NSString *type in directTypes) {
        [[self actionsArrayForType:type] addObject:action];
    }
    
	if ([directTypes containsObject:QSFilePathType]) {
		directTypes = [actionDict objectForKey:@"directFileTypes"];
		if (![directTypes count]) directTypes = [NSArray arrayWithObject:@"*"];
		for (NSString *type in directTypes) {
			[[self actionsArrayForFileType:type] addObject:action];
		}
	}
	}
}
	
- (void)updateRanks {
	int i;
	for(i = 0; i<[actionRanking count]; i++) {
		[[actionIdentifiers objectForKey:[actionRanking objectAtIndex:i]] _setRank:i];
	}
	[self writeActionsInfo];
}

- (NSMutableArray *)getArrayForSource:(NSString *)sourceid {
	return [actionSources objectForKey:sourceid];
//	NSMutableArray *array = [actionSources objectForKey:sourceid];
//	return array;
}

- (NSMutableArray *)makeArrayForSource:(NSString *)sourceid {
	NSMutableArray *array = [actionSources objectForKey:sourceid];
	if (!array) [actionSources setObject:(array = [NSMutableArray array]) forKey:sourceid];
	return array;
}

//- (void)registerActions:(id)actionObject {
//	if (!actionObject) return;
//	[oldActionObjects addObject:actionObject];
//	[self performSelectorOnMainThread:@selector(loadActionsForObject:) withObject:actionObject waitUntilDone:YES];
//}

//- (void)loadActionsForObject:(id)actionObject {
//	NSEnumerator *actionEnumerator = [[actionObject actions] objectEnumerator];
//	id action;
//	while (action = [actionEnumerator nextObject]) {
//		if ([action identifier])
//			[actionIdentifiers setObject:action forKey:[action identifier]];
//	}
//}


- (NSArray *)actions {
	return [actionIdentifiers allValues];
}

- (QSAction *)actionForIdentifier:(NSString *)identifier {
	return [actionIdentifiers objectForKey:identifier];
}

- (QSObject *)performAction:(NSString *)action directObject:(QSObject *)dObject indirectObject:(QSObject *)iObject {
	// NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	QSAction *actionObject = [actionIdentifiers objectForKey:action];
	if (actionObject)
		return [actionObject performOnDirectObject:dObject indirectObject:iObject];
	else
		NSLog(@"Action not found: %@", action);
	return nil;
}



- (NSArray *)rankedActionsForDirectObject:(QSObject *)dObject indirectObject:(QSObject *)iObject {
	return [self rankedActionsForDirectObject:dObject indirectObject:iObject shouldBypass:NO];
}

- (NSArray *)rankedActionsForDirectObject:(QSObject *)dObject indirectObject:(QSObject *)iObject shouldBypass:(BOOL)bypass {
	if (!dObject) {
		return nil;
	}
	
	NSArray *actions = nil;
	if ([[dObject handler] respondsToSelector:@selector(actionsForDirectObject:indirectObject:)]) {
		actions = (NSMutableArray *)[[dObject handler] actionsForDirectObject:dObject indirectObject:iObject];
	}
    
	BOOL bypassValidation =
		(bypass && [dObject isKindOfClass:[QSProxyObject class]] && [(QSProxyObject *)dObject bypassValidation]);

	if (bypassValidation) {
		//NSLog(@"bypass? %@ %@", dObject, NSStringFromClass([dObject class]) );
		actions = [[[actionIdentifiers allValues] mutableCopy] autorelease];
	}
	
	if (!actions) {
		actions = [self validActionsForDirectObject:dObject indirectObject:iObject];
	}

	NSString *preferredActionID = [dObject objectForMeta:kQSObjectDefaultAction];

	id preferredAction = nil;
    if (preferredActionID) {
		preferredAction = [self actionForIdentifier:preferredActionID];
	}

	//	NSLog(@"prefer \"%@\"", preferredActionID);
	//	NSLog(@"actions %d", [actions count]);
#if 1
	NSSortDescriptor *rankDescriptor = [[NSSortDescriptor alloc] initWithKey:@"rank" ascending:YES];
	actions = [actions sortedArrayUsingDescriptors:[NSArray arrayWithObject:rankDescriptor]];
	[rankDescriptor release];
#else
	actions = [[QSLibrarian sharedInstance] scoredArrayForString:[NSString stringWithFormat:@"QSActionMnemonic:%@", [dObject primaryType]] inSet:actions mnemonicsOnly:YES];
#endif

	if (preferredAction) {
		actions = [NSArray arrayWithObjects:preferredAction, actions, nil];
	}
	return actions;
}

- (NSArray *)validActionsForDirectObject:(QSObject *)dObject indirectObject:(QSObject *)iObject fromSource:(id)aObject types:(NSSet *)dTypes fileType:(NSString *)fileType {
	if (dTypes) {
		NSMutableSet *aTypes = [NSMutableSet setWithArray:[aObject types]];

		if ([aTypes count]) {
			[aTypes intersectSet:dTypes];
			if (![aTypes count]) return nil;
			if ([aTypes containsObject:QSFilePathType] && [aObject fileTypes] && ([aTypes count] == 1 || [[dObject primaryType] isEqualToString:QSFilePathType]) ) {
				if (![[aObject fileTypes] containsObject:fileType]) return nil;
			}
		}
	}
	NSArray *actions = nil;
	@try {
		actions = [aObject validActionsForDirectObject:dObject indirectObject:iObject];
	} @catch (NSException *localException) {
		NSLog(@"[Quicksilver %s]: localException = '%@'", __PRETTY_FUNCTION__, [localException description]);
	}
	return actions;
}

- (void)logActions {}

- (NSArray *)validActionsForDirectObject:(QSObject *)dObject indirectObject:(QSObject *)iObject {
	if (!dObject) {
		return nil;
	}
	
	NSMutableArray *validActions = [NSMutableArray array];
	
#ifdef DEBUG
	// Used for logging the time taken to create the actions
	NSDate *startDate = [NSDate date];
#endif

	NSString *fileType = [dObject singleFileType];
	NSArray *newActions = [self actionsForTypes:[dObject types] fileTypes:(fileType ? [NSArray arrayWithObject:fileType] : nil)];
	
	// for loop vars
	BOOL isValid;
	id aObject = nil;
	NSArray *validSourceActions;
	NSMutableDictionary *validatedActionsBySource = [NSMutableDictionary dictionary];

	/* Validate the actions
	   The actions will validate if either
	      a) The action is valid for ALL object types (no 'validatesObjects' key in the Info.plist) or
	      b) the action provider (the 'actionClass' string set in the Info.plist) method [validActionsForDirectObject:dObject indirectObject:iObject]
	         returns an array containing this action.
	*/
    for (QSAction *thisAction in newActions) {
		validSourceActions = nil;
		NSDictionary *actionDict = [thisAction objectForType:QSActionType];
		isValid = ![[actionDict objectForKey:kActionValidatesObjects] boolValue];
                
		if (!isValid) {
			validSourceActions = [validatedActionsBySource objectForKey:[actionDict objectForKey:kActionClass]];
			if (!validSourceActions) {
                
				aObject = [thisAction provider];
				validSourceActions = [self validActionsForDirectObject:dObject indirectObject:iObject fromSource:aObject types:nil fileType:nil];
				NSString *className = NSStringFromClass([aObject class]);
				if (className) {
					[validatedActionsBySource setObject:validSourceActions?validSourceActions:[NSArray array] forKey:className];
				}
			}
            
			isValid = [validSourceActions containsObject:[thisAction identifier]];
		}
		
		if (isValid) [validActions addObject:thisAction];
	
    }

	if (![validActions count]) {
		NSLog(@"unable to find actions for %@", actionIdentifiers);
		NSLog(@"types %@ %@", [NSSet setWithArray:[dObject types]], fileType);
		return nil;
	}
#ifdef DEBUG
	if (VERBOSE) {
		NSLog(@"Took %dµs to sort actions for dObject: %@",(int)(-[startDate timeIntervalSinceNow] *1000000),[dObject name]);
	}
#endif
	return [[validActions mutableCopy] autorelease];
}

- (NSArray *)validIndirectObjectsForAction:(NSString *)action directObject:(QSObject *)dObject {
	QSActionProvider *actionObject = [[actionIdentifiers objectForKey:action] objectForKey:kActionClass];
	//  NSLog(@"actionobject %@", actionObject);
	return [actionObject validIndirectObjectsForAction:action directObject:dObject];
}

-(void) addActionToEnabledActions:(QSAction *)action {
	NSString *ident = [action identifier];
	[enabledActions addObject:ident];
	[disabledActions removeObject:ident];
}

-(void) removeActionFromEnabledActions:(QSAction *)action {
	NSString *ident = [action identifier];
	[disabledActions addObject:ident];
	[enabledActions removeObject:ident];
}


- (BOOL)actionIsEnabled:(QSAction*)action {
    return [enabledActions containsObject:[action identifier]];;
}
- (void)setAction:(QSAction *)action isEnabled:(BOOL)enabled {

	if (enabled) {
		[self addActionToEnabledActions:action];
	}
	else {
		[self removeActionFromEnabledActions:action];
	}

	[self writeActionsInfo];
}

- (BOOL)actionIsMenuEnabled:(QSAction*)action {
    id val = [actionMenuActivation objectForKey:[action identifier]];
    return (val ? [val boolValue] : YES);
}
- (void)setAction:(QSAction *)action isMenuEnabled:(BOOL)flag {
// 	if (VERBOSE) NSLog(@"set action %@ is menu enabled %d", action, flag);
	[actionMenuActivation setObject:[NSNumber numberWithBool:flag] forKey:[action identifier]];
	[self writeActionsInfo];
}

- (void)orderActions:(NSArray *)actions aboveActions:(NSArray *)lowerActions {
	int index = [[lowerActions valueForKeyPath:@"@min.rank"] intValue];
#ifdef DEBUG
	if (VERBOSE) NSLog(@"Promote to %d", index);
#endif
	NSString *targetIdentifier = [actionRanking objectAtIndex:index];
	NSArray *identifiers = [actions valueForKey:@"identifier"];
	[actionRanking removeObjectsInArray:identifiers];
	index = [actionRanking indexOfObject:targetIdentifier];
	[actionRanking insertObjectsFromArray:identifiers atIndex:index];
	[self updateRanks];
}
- (void)orderActions:(NSArray *)actions belowActions:(NSArray *)higherActions {
	int index = [[higherActions valueForKeyPath:@"@max.rank"] intValue];
	//NSLog(@"demote to %d", index);
	NSString *targetIdentifier = [actionRanking objectAtIndex:index];
	NSArray *identifiers = [actions valueForKey:@"identifier"];
	[actionRanking removeObjectsInArray:identifiers];
	index = [actionRanking indexOfObject:targetIdentifier];
	[actionRanking insertObjectsFromArray:identifiers atIndex:index+1];
	[self updateRanks];
}
- (void)noteIndirect:(QSObject *)iObject forAction:(QSObject *)aObject {
	NSString *iIdent = [iObject identifier];
	if (!iIdent) return;
	NSString *aIdent = [aObject identifier];
	NSMutableArray *array;
	if (!(array = [actionIndirects objectForKey:aIdent]) )
		[actionIndirects setObject:(array = [NSMutableArray array]) forKey:aIdent];
	[array removeObject:iIdent];
	[array insertObject:iIdent atIndex:0];
	if ([array count] >15) [array removeObjectsInRange:NSMakeRange(15, [array count] -15)];
	[self performSelector:@selector(writeActionsInfoNow) withObject:nil afterDelay:5.0 extend:YES];
}

- (void)noteNewName:(NSString *)name forAction:(QSObject *)aObject {
	NSString *aIdent = [aObject identifier];
	if (!name)
		[actionNames removeObjectForKey:aIdent];
	else
		[actionNames setObject:name forKey:aIdent];
	[self performSelector:@selector(writeActionsInfoNow) withObject:nil afterDelay:5.0 extend:YES];
}

- (void)writeActionsInfo {
	[self performSelector:@selector(writeActionsInfoNow) withObject:nil afterDelay:3.0 extend:YES];
}
- (void)writeActionsInfoNow {
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	[dict setObject:actionPrecedence forKey:@"actionPrecedence"];
	[dict setObject:actionRanking forKey:@"actionRanking"];
	[dict setObject:[NSDictionary dictionaryWithObjectsAndKeys:enabledActions, @"enabledActions", disabledActions, @"disabledActions",nil] forKey:@"actionActivation"];
	[dict setObject:actionMenuActivation forKey:@"actionMenuActivation"];
	[dict setObject:actionIndirects forKey:@"actionIndirects"];
	[dict setObject:actionNames forKey:@"actionNames"];
	[dict writeToFile:pQSActionsLocation atomically:YES];
	[dict release];
	
#ifdef DEBUG
	if (VERBOSE) NSLog(@"Wrote Actions Info");
#endif
}
@end


@implementation QSExecutor (QSPlugInInfo)
- (BOOL)handleInfo:(id)info ofType:(NSString *)type fromBundle:(NSBundle *)bundle {
	if (info) {
        NSDictionary *actionDict;
        for (NSString *key in info) {
            actionDict = [info objectForKey:key];
            if ([[actionDict objectForKey:kItemFeatureLevel] intValue] > [NSApp featureLevel]) {
                NSString * actionIdentifier = [actionDict objectForKey:kItemID];
                if (!actionIdentifier) {
                    NSLog(@"Prevented load of unidentified action from bundle %@ because the action's featureLevel (set from its Info.plist) is higher than NSApp's current featureLevel. This is not neccessarily an error. Sometimes this mechanism is used to prevent unstable actions from loading.", [[bundle bundlePath] lastPathComponent]);
                } else {
                    NSLog(@"Prevented load of action %@ because it's featureLevel (set from its Info.plist) is higher than NSApp's current featureLevel. This is not neccessarily an error. Sometimes this mechanism is used to prevent unstable actions from loading.", actionIdentifier);
                }
                continue;
            }
            
            QSAction *action = [QSAction actionWithDictionary:actionDict identifier:key];
            [action setBundle:bundle];
            
            if ([[actionDict objectForKey:kActionInitialize] boolValue] && [[action provider] respondsToSelector:@selector(initializeAction:)])
                action = [[action provider] initializeAction:action];
            
            if (action) {
                [self addAction:action];
				if ([action enabled]) {
                [[self makeArrayForSource:[bundle bundleIdentifier]] addObject:action];
				}
            }
        }
	} else {
		//		NSDictionary *providers = [[[plugin bundle] dictionaryForFileOrPlistKey:@"QSRegistration"] objectForKey:@"QSActionProviders"];
		//		if (providers) {
		//				[self loadOldActionProviders:[providers allValues]];
		//		}
	}
	return YES;
}
@end
