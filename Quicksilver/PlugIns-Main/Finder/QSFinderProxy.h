#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <QSFoundation/QSFoundation.h>
#import <QSCore/QSCore.h>
#import "QSFSBrowserMediator.h"

// Scripting Bridge
#import "Finder.h"

#define kFinderOpenTrashAction @"FinderOpenTrashAction"
#define kFinderEmptyTrashAction @"FinderEmptyTrashAction"

@interface QSFinderProxy : NSObject <QSFSBrowserMediator> {
    FinderApplication *finder;
NSAppleScript *finderScript;
}
+ (id)sharedInstance;

- (BOOL)revealFile:(NSString *)file;
- (NSArray *)selection;
- (NSArray *)copyFiles:(NSArray *)files toFolder:(NSString *)destination NS_RETURNS_NOT_RETAINED;
- (NSArray *)moveFiles:(NSArray *)files toFolder:(NSString *)destination;
- (NSArray *)moveFiles:(NSArray *)files toFolder:(NSString *)destination shouldCopy:(BOOL)copy;
- (NSArray *)deleteFiles:(NSArray *)files;

- (NSAppleScript *)finderScript;
- (void)setFinderScript:(NSAppleScript *)aFinderScript;

@end
