//
//  SyncNodeInfo.h
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 20/09/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class SyncNodeInfo, SyncRepository, SyncError;

@interface SyncNodeInfo : NSManagedObject

@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSNumber *isFolder;
@property (nonatomic, retain) NSNumber *isUnfavoritedHasLocalChanges;
@property (nonatomic, retain) NSNumber *isTopLevelSyncNode;
@property (nonatomic, retain) NSNumber *reloadContent;
@property (nonatomic, retain) NSDate *lastDownloadedDate;
@property (nonatomic, retain) NSData *node;
@property (nonatomic, retain) NSString *syncContentPath;
@property (nonatomic, retain) NSString *syncNodeInfoId;
@property (nonatomic, retain) NSSet *nodes;
@property (nonatomic, retain) SyncNodeInfo *parentNode;
@property (nonatomic, retain) SyncRepository *repository;
@property (nonatomic, retain) SyncError *syncError;
@end

@interface SyncNodeInfo (CoreDataGeneratedAccessors)

- (void)addNodesObject:(SyncNodeInfo *)value;
- (void)removeNodesObject:(SyncNodeInfo *)value;
- (void)addNodes:(NSSet *)values;
- (void)removeNodes:(NSSet *)values;

@end
