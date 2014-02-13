//
//  SyncHelper.m
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 24/09/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import "SyncHelper.h"
#import "SyncNodeInfo.h"
#import "SyncAccount.h"
#import "CoreDataSyncHelper.h"
#import "SyncNodeStatus.h"

NSString * const kLastDownloadedDateKey = @"lastDownloadedDate";
NSString * const kSyncNodeKey = @"node";
NSString * const kSyncContentPathKey = @"contentPath";
NSString * const kSyncReloadContentKey = @"reloadContent";

@interface SyncHelper ()
@property (nonatomic, strong) AlfrescoFileManager *fileManager;
@property (nonatomic, strong) CoreDataSyncHelper *syncCoreDataHelper;
@end

@implementation SyncHelper

+ (SyncHelper *)sharedHelper
{
    static dispatch_once_t predicate = 0;
    __strong static id sharedObject = nil;
    dispatch_once(&predicate, ^{
        sharedObject = [[self alloc] init];
    });
    return sharedObject;
}

- (void)updateLocalSyncInfoWithRemoteInfo:(NSDictionary *)syncNodesInfo
                         forAccountWithId:(NSString *)accountId
                             preserveInfo:(NSDictionary *)info
                              permissions:(NSDictionary *)permissions
                 refreshExistingSyncNodes:(BOOL)refreshExisting
                   inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    @autoreleasepool
    {
        if (refreshExisting)
        {
            // refresh data in Database for account
            [self deleteStoredInfoForAccountWithId:accountId inManagedObjectContext:managedContext];
        }
        
        SyncAccount *syncAccount = [self.syncCoreDataHelper accountObjectForAccountWithId:accountId inManagedObjectContext:managedContext];
        if (!syncAccount)
        {
            syncAccount = [self.syncCoreDataHelper createSyncAccountMangedObjectInManagedObjectContext:managedContext];
            syncAccount.accountId = accountId;
        }
        NSMutableArray *syncNodesInfoKeys = [[syncNodesInfo allKeys] mutableCopy];
        
        NSArray *topLevelSyncItems = [syncNodesInfo objectForKey:accountId];
        
        [self populateNodes:topLevelSyncItems inParentFolder:syncAccount.accountId forAccountWithId:accountId preserveInfo:info permissions:permissions inManagedObjectContext:managedContext];
        [syncNodesInfoKeys removeObject:accountId];
        
        for (NSString *syncFolderInfoKey in syncNodesInfoKeys)
        {
            NSArray *nodesInFolder = [syncNodesInfo objectForKey:syncFolderInfoKey];
            
            if (nodesInFolder.count > 0)
            {
                [self populateNodes:nodesInFolder inParentFolder:syncFolderInfoKey forAccountWithId:accountId preserveInfo:info permissions:permissions inManagedObjectContext:managedContext];
            }
        }
        [self.syncCoreDataHelper saveContextForManagedObjectContext:managedContext];
        [managedContext reset];
    }
}

- (void)deleteStoredInfoForAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"account.accountId == %@", accountId];
    NSArray *allNodeInfos = [self.syncCoreDataHelper retrieveRecordsForTable:kSyncNodeInfoManagedObject withPredicate:predicate inManagedObjectContext:managedContext];
    for (SyncNodeInfo *nodeInfo in allNodeInfos)
    {
        // delete all sync node info records for current account so we get everything refreshed (except if file is changed locally but has changes - will be deleted after its uploaded)
        BOOL isRemovedFromSyncHasLocalChanges = [nodeInfo.isRemovedFromSyncHasLocalChanges intValue];
        if (!isRemovedFromSyncHasLocalChanges)
        {
            [self.syncCoreDataHelper deleteRecordForManagedObject:nodeInfo inManagedObjectContext:managedContext];
        }
        [self.syncCoreDataHelper deleteRecordForManagedObject:nodeInfo.syncError inManagedObjectContext:managedContext];
    }
}

- (void)populateNodes:(NSArray *)nodes
       inParentFolder:(NSString *)folderId
     forAccountWithId:(NSString *)accountId
         preserveInfo:(NSDictionary *)info
          permissions:(NSDictionary *)permissions inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    BOOL (^updateInfoWithExistingInfoForSyncNode)(SyncNodeInfo *) = ^ BOOL (SyncNodeInfo *nodeInfo)
    {
        NSDictionary *infoTobePreserved = [info objectForKey:nodeInfo.syncNodeInfoId];
        
        if (infoTobePreserved)
        {
            nodeInfo.reloadContent = [infoTobePreserved objectForKey:kSyncReloadContentKey];
            nodeInfo.lastDownloadedDate = [infoTobePreserved objectForKey:kLastDownloadedDateKey];
            nodeInfo.syncContentPath = [infoTobePreserved objectForKey:kSyncContentPathKey];
        }
        return YES;
    };
    
    SyncAccount *syncAccount = [self.syncCoreDataHelper accountObjectForAccountWithId:accountId inManagedObjectContext:managedContext];
    BOOL isTopLevelSyncNode = ([folderId isEqualToString:accountId]);
    
    // retrieve existing or create new parent folder in managed context
    id parentNodeInfo = nil;
    if (isTopLevelSyncNode)
    {
        parentNodeInfo = syncAccount;
    }
    else
    {
        parentNodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:folderId inAccountWithId:accountId inManagedObjectContext:managedContext];
        if (parentNodeInfo == nil)
        {
            parentNodeInfo = [self.syncCoreDataHelper createSyncNodeInfoMangedObjectInManagedObjectContext:managedContext];
            [parentNodeInfo setSyncNodeInfoId:folderId];
            [parentNodeInfo setAccount:syncAccount];
            [parentNodeInfo setIsTopLevelSyncNode:[NSNumber numberWithBool:isTopLevelSyncNode]];
            [parentNodeInfo setIsFolder:[NSNumber numberWithBool:YES]];
        }
    }
    
    // populate parent folder with its children nodes
    for (AlfrescoNode *alfrescoNode in nodes)
    {
        // check if we already have object in managedContext for alfrescoNode
        SyncNodeInfo *syncNodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:alfrescoNode.identifier inAccountWithId:accountId inManagedObjectContext:managedContext];
        NSData *archivedNode = [NSKeyedArchiver archivedDataWithRootObject:alfrescoNode];
        NSData *archivedPermissions = nil;
        AlfrescoPermissions *nodePermissions = [permissions objectForKey:alfrescoNode.identifier];
        if (nodePermissions)
        {
            archivedPermissions = [NSKeyedArchiver archivedDataWithRootObject:nodePermissions];
        }
        
        // create new nodeInfo for node if it does not exist yet
        if (!syncNodeInfo)
        {
            syncNodeInfo = [self.syncCoreDataHelper createSyncNodeInfoMangedObjectInManagedObjectContext:managedContext];
            syncNodeInfo.syncNodeInfoId = alfrescoNode.identifier;
            syncNodeInfo.isFolder = [NSNumber numberWithBool:alfrescoNode.isFolder];
            syncNodeInfo.account = syncAccount;
        }
        syncNodeInfo.title = alfrescoNode.name;
        syncNodeInfo.node = archivedNode;
        syncNodeInfo.isTopLevelSyncNode = [NSNumber numberWithBool:isTopLevelSyncNode];
        
        if (archivedPermissions)
        {
            syncNodeInfo.permissions = archivedPermissions;
        }
        
        // update node info with existing info for documents (will set their new info once they are successfully downloaded) - for folders update their nodes
        if (!alfrescoNode.isFolder)
        {
            updateInfoWithExistingInfoForSyncNode(syncNodeInfo);
        }
        
        [parentNodeInfo addNodesObject:syncNodeInfo];
    }
}

- (NSString *)syncNameForNode:(AlfrescoNode *)node inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:node.identifier inAccountWithId:accountId inManagedObjectContext:managedContext];
    
    if (nodeInfo.syncContentPath == nil || [nodeInfo.syncContentPath isEqualToString:@""])
    {
        NSString *newName = @"";
        NSString *nodeExtension = [node.name pathExtension];
        
        if (nodeExtension == nil || [nodeExtension isEqualToString:@""])
        {
            newName = [node.identifier lastPathComponent];
        }
        else
        {
            newName = [NSString stringWithFormat:@"%@.%@", [node.identifier lastPathComponent], nodeExtension];
        }
        return newName;
    }
    return [nodeInfo.syncContentPath lastPathComponent];
}

- (NSString *)syncContentDirectoryPathForAccountWithId:(NSString *)accountId
{
    NSString *contentDirectory = [self.fileManager syncFolderPath];
    if (accountId)
    {
        contentDirectory = [contentDirectory stringByAppendingPathComponent:accountId];
    }
    BOOL isDirectory;
    BOOL dirExists = [self.fileManager fileExistsAtPath:contentDirectory isDirectory:&isDirectory];
    NSError *error = nil;
    
    if (!dirExists)
    {
        [self.fileManager createDirectoryAtPath:contentDirectory withIntermediateDirectories:YES attributes:nil error:&error];
    }

    return contentDirectory;
}

#pragma mark - SyncInfo Utilities

- (AlfrescoNode *)localNodeForNodeId:(NSString *)nodeId inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:nodeId inAccountWithId:accountId inManagedObjectContext:managedContext];
    if (nodeInfo.node)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:nodeInfo.node];
    }
    return nil;
}

- (NSDate *)lastDownloadedDateForNode:(AlfrescoNode *)node inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:node.identifier inAccountWithId:accountId inManagedObjectContext:managedContext];
    return nodeInfo.lastDownloadedDate;
}

- (void)resolvedObstacleForDocument:(AlfrescoDocument *)document inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    // once sync problem is resolved (document synced or saved) set its isUnfavoritedHasLocalChanges flag to NO so node is deleted later
    SyncNodeInfo *nodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:document.identifier inAccountWithId:accountId inManagedObjectContext:managedContext];
    nodeInfo.isRemovedFromSyncHasLocalChanges = [NSNumber numberWithBool:NO];
    [self.syncCoreDataHelper saveContextForManagedObjectContext:managedContext];
}

- (SyncNodeStatus *)syncNodeStatusObjectForNodeWithId:(NSString *)nodeId inSyncNodesStatus:(NSDictionary *)syncStatuses
{
    SyncNodeStatus *nodeStatus = [syncStatuses objectForKey:nodeId];
    
    if (!nodeStatus && nodeId)
    {
        nodeStatus = [[SyncNodeStatus alloc] initWithNodeId:nodeId];
        [syncStatuses setValue:nodeStatus forKey:nodeId];
    }
    
    return nodeStatus;
}

#pragma mark - Delete Methods

- (void)deleteNodeFromSync:(AlfrescoNode *)node inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSString *nodeSyncName = [self syncNameForNode:node inAccountWithId:accountId inManagedObjectContext:managedContext];
    NSString *syncNodeContentPath = [[self syncContentDirectoryPathForAccountWithId:accountId] stringByAppendingPathComponent:nodeSyncName];
    
    NSError *error = nil;
    [self.fileManager removeItemAtPath:syncNodeContentPath error:&error];
    
    if (!error)
    {
        SyncNodeInfo *nodeInfo = [self.syncCoreDataHelper nodeInfoForObjectWithNodeId:node.identifier inAccountWithId:accountId inManagedObjectContext:managedContext];
        [self.syncCoreDataHelper deleteRecordForManagedObject:nodeInfo inManagedObjectContext:managedContext];
    }
}

- (void)deleteNodesFromSync:(NSArray *)array inAccountWithId:(NSString *)accountId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    for (AlfrescoNode *node in array)
    {
        [self deleteNodeFromSync:node inAccountWithId:accountId inManagedObjectContext:managedContext];
    }
    [self.syncCoreDataHelper saveContextForManagedObjectContext:managedContext];
}

- (void)removeSyncContentAndInfoInManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSString *syncContentDirectory = [self syncContentDirectoryPathForAccountWithId:nil];
    NSError *error = nil;
    [self.fileManager removeItemAtPath:syncContentDirectory error:&error];
    
    if (!error)
    {
        [self.syncCoreDataHelper deleteAllRecordsInTable:kSyncAccountManagedObject inManagedObjectContext:managedContext];
        [self.syncCoreDataHelper deleteAllRecordsInTable:kSyncNodeInfoManagedObject inManagedObjectContext:managedContext];
        [self.syncCoreDataHelper saveContextForManagedObjectContext:managedContext];
    }
}

#pragma mark - Private Interface

- (id)init
{
    self = [super init];
    if (self)
    {
        self.fileManager = [AlfrescoFileManager sharedManager];
        self.syncCoreDataHelper = [[CoreDataSyncHelper alloc] init];
    }
    return self;
}

@end
