//
//  SyncHelper.m
//  AlfrescoApp
//
//  Created by Mohamad Saeedi on 24/09/2013.
//  Copyright (c) 2013 Alfresco. All rights reserved.
//

#import "SyncHelper.h"
#import "SyncNodeInfo.h"
#import "SyncRepository.h"
#import "CoreDataUtils.h"
#import "SyncNodeStatus.h"

NSString * const kLastDownloadedDateKey = @"lastDownloadedDate";
NSString * const kSyncNodeKey = @"node";
NSString * const kSyncContentPathKey = @"contentPath";
NSString * const kSyncReloadContentKey = @"reloadContent";

static NSString * const kSyncContentDirectory = @"sync";

@interface SyncHelper ()
@property (nonatomic, strong) AlfrescoFileManager *fileManager;
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
                      forRepositoryWithId:(NSString *)repositoryId
                             preserveInfo:(NSDictionary *)info
                 refreshExistingSyncNodes:(BOOL)refreshExisting
                   inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    if (refreshExisting)
    {
        // refresh data in Database for repository
        [self deleteStoredInfoForRepository:repositoryId inManagedObjectContext:managedContext];
    }
    
    SyncRepository *syncRepository = [CoreDataUtils repositoryObjectForRepositoryWithId:repositoryId inManagedObjectContext:managedContext];
    if (!syncRepository)
    {
        syncRepository = [CoreDataUtils createSyncRepoMangedObjectInManagedObjectContext:managedContext];
        syncRepository.repositoryId = repositoryId;
    }
    NSMutableArray *syncNodesInfoKeys = [[syncNodesInfo allKeys] mutableCopy];
    
    NSArray *topLevelSyncItems = [syncNodesInfo objectForKey:repositoryId];
    
    [self populateNodes:topLevelSyncItems inParentFolder:syncRepository.repositoryId forRepository:repositoryId preserveInfo:info inManagedObjectContext:managedContext];
    [syncNodesInfoKeys removeObject:repositoryId];
    
    for (NSString *syncFolderInfoKey in syncNodesInfoKeys)
    {
        NSArray *nodesInFolder = [syncNodesInfo objectForKey:syncFolderInfoKey];
        
        if (nodesInFolder.count > 0)
        {
            [self populateNodes:nodesInFolder inParentFolder:syncFolderInfoKey forRepository:repositoryId preserveInfo:info inManagedObjectContext:managedContext];
        }
    }
    [CoreDataUtils saveContextForManagedObjectContext:managedContext];
}

- (void)deleteStoredInfoForRepository:(NSString *)repositoryId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSArray *allNodeInfos = [CoreDataUtils retrieveRecordsForTable:kSyncNodeInfoManagedObject inManagedObjectContext:managedContext];
    for (SyncNodeInfo *nodeInfo in allNodeInfos)
    {
        // delete all sync node info records for current repository so we get everything refreshed (except if file is changed locally but has changes - will be deleted after its uploaded)
        BOOL isUnfavoritedHasLocalChanges = [nodeInfo.isUnfavoritedHasLocalChanges intValue];
        if (!isUnfavoritedHasLocalChanges && [nodeInfo.repository.repositoryId isEqualToString:repositoryId])
        {
            [CoreDataUtils deleteRecordForManagedObject:nodeInfo inManagedObjectContext:managedContext];
        }
        [CoreDataUtils deleteRecordForManagedObject:nodeInfo.syncError inManagedObjectContext:managedContext];
    }
}

- (void)populateNodes:(NSArray *)nodes inParentFolder:(NSString *)folderId forRepository:(NSString *)repositoryId preserveInfo:(NSDictionary *)info inManagedObjectContext:(NSManagedObjectContext *)managedContext
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
    
    SyncRepository *repository = [CoreDataUtils repositoryObjectForRepositoryWithId:repositoryId inManagedObjectContext:managedContext];
    BOOL isTopLevelSyncNode = ([folderId isEqualToString:repositoryId]);
    
    // retrieve existing or create new parent folder in managed context
    id parentNodeInfo = nil;
    if (isTopLevelSyncNode)
    {
        parentNodeInfo = repository;
    }
    else
    {
        parentNodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:folderId inManagedObjectContext:managedContext];
        if (parentNodeInfo == nil)
        {
            parentNodeInfo = [CoreDataUtils createSyncNodeInfoMangedObjectInManagedObjectContext:managedContext];
            [parentNodeInfo setSyncNodeInfoId:folderId];
            [parentNodeInfo setRepository:repository];
            [parentNodeInfo setIsTopLevelSyncNode:[NSNumber numberWithBool:isTopLevelSyncNode]];
            [parentNodeInfo setIsFolder:[NSNumber numberWithBool:YES]];
        }
    }
    
    // populate parent folder with its children nodes
    for (AlfrescoNode *alfrescoNode in nodes)
    {
        // check if we already have object in managedContext for alfrescoNode
        SyncNodeInfo *syncNodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:alfrescoNode.identifier inManagedObjectContext:managedContext];
        NSData *archivedNode = [NSKeyedArchiver archivedDataWithRootObject:alfrescoNode];
        
        // create new nodeInfo for node if it does not exist yet
        if (!syncNodeInfo)
        {
            syncNodeInfo = [CoreDataUtils createSyncNodeInfoMangedObjectInManagedObjectContext:managedContext];
            syncNodeInfo.syncNodeInfoId = alfrescoNode.identifier;
            syncNodeInfo.isTopLevelSyncNode = [NSNumber numberWithBool:isTopLevelSyncNode];
            syncNodeInfo.isFolder = [NSNumber numberWithBool:alfrescoNode.isFolder];
            syncNodeInfo.repository = repository;
        }
        syncNodeInfo.title = alfrescoNode.name;
        syncNodeInfo.node = archivedNode;
        
        // update node info with existing info for documents (will set their new info once they are successfully downloaded) - for folders update their nodes
        if (!alfrescoNode.isFolder)
        {
            updateInfoWithExistingInfoForSyncNode(syncNodeInfo);
        }
        
        [parentNodeInfo addNodesObject:syncNodeInfo];
    }
}

- (NSString *)syncNameForNode:(AlfrescoNode *)node inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:node.identifier inManagedObjectContext:managedContext];
    
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

- (NSString *)syncContentDirectoryPathForRepository:(NSString *)repositoryId
{
    NSString *contentDirectory = [self.fileManager.documentsDirectory stringByAppendingPathComponent:kSyncContentDirectory];
    if (repositoryId)
    {
        contentDirectory = [contentDirectory stringByAppendingPathComponent:repositoryId];
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

- (AlfrescoNode *)localNodeForNodeId:(NSString *)nodeId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:nodeId inManagedObjectContext:managedContext];
    if (nodeInfo.node)
    {
        return [NSKeyedUnarchiver unarchiveObjectWithData:nodeInfo.node];
    }
    return nil;
}

- (NSDate *)lastDownloadedDateForNode:(AlfrescoNode *)node inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    SyncNodeInfo *nodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:node.identifier inManagedObjectContext:managedContext];
    return nodeInfo.lastDownloadedDate;
}

- (void)resolvedObstacleForDocument:(AlfrescoDocument *)document inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    // once sync problem is resolved (document synced or saved) set its isUnfavoritedHasLocalChanges flag to NO so node is deleted later
    SyncNodeInfo *nodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:document.identifier inManagedObjectContext:managedContext];
    nodeInfo.isUnfavoritedHasLocalChanges = [NSNumber numberWithBool:NO];
    [CoreDataUtils saveContextForManagedObjectContext:managedContext];
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

- (void)deleteNodeFromSync:(AlfrescoNode *)node inRepitory:(NSString *)repositoryId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSString *nodeSyncName = [self syncNameForNode:node inManagedObjectContext:managedContext];
    NSString *syncNodeContentPath = [[self syncContentDirectoryPathForRepository:repositoryId] stringByAppendingPathComponent:nodeSyncName];
    
    NSError *error = nil;
    [self.fileManager removeItemAtPath:syncNodeContentPath error:&error];
    
    if (!error)
    {
        SyncNodeInfo *nodeInfo = [CoreDataUtils nodeInfoForObjectWithNodeId:node.identifier inManagedObjectContext:managedContext];
        [CoreDataUtils deleteRecordForManagedObject:nodeInfo inManagedObjectContext:managedContext];
    }
}

- (void)deleteNodesFromSync:(NSArray *)array inRepitory:(NSString *)repositoryId inManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    for (AlfrescoNode *node in array)
    {
        [self deleteNodeFromSync:node inRepitory:repositoryId inManagedObjectContext:managedContext];
    }
    [CoreDataUtils saveContextForManagedObjectContext:managedContext];
}

- (void)removeSyncContentAndInfoInManagedObjectContext:(NSManagedObjectContext *)managedContext
{
    NSString *syncContentDirectory = [self syncContentDirectoryPathForRepository:nil];
    NSError *error = nil;
    [self.fileManager removeItemAtPath:syncContentDirectory error:&error];
    
    if (!error)
    {
        [CoreDataUtils deleteAllRecordsInTable:kSyncRepoManagedObject inManagedObjectContext:managedContext];
        [CoreDataUtils deleteAllRecordsInTable:kSyncNodeInfoManagedObject inManagedObjectContext:managedContext];
        [CoreDataUtils saveContextForManagedObjectContext:managedContext];
    }
}

#pragma mark - Private Interface

- (id)init
{
    self = [super init];
    if (self)
    {
        self.fileManager = [AlfrescoFileManager sharedManager];
    }
    return self;
}

@end