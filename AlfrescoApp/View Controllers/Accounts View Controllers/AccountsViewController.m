/*******************************************************************************
 * Copyright (C) 2005-2016 Alfresco Software Limited.
 * 
 * This file is part of the Alfresco Mobile iOS App.
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *  
 *  http://www.apache.org/licenses/LICENSE-2.0
 * 
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 ******************************************************************************/
 
#import "AccountsViewController.h"
#import "AccountManager.h"
#import "AccountTypeSelectionViewController.h"
#import "NavigationViewController.h"
#import "AccountInfoViewController.h"
#import "LoginManager.h"
#import "AccountInfoViewController.h"
#import "UniversalDevice.h"
#import "PinViewController.h"
#import "PreferenceManager.h"
#import "TouchIDManager.h"
#import "RealmSyncManager.h"
#import "SecurityManager.h"

static NSInteger const kAccountSelectionButtonWidth = 32;
static NSInteger const kAccountSelectionButtongHeight = 32;

static NSInteger const kAccountRowNumber = 0;
static NSInteger const kNetworksStartRowNumber = 1;

static CGFloat const kDefaultFontSize = 18.0f;

static CGFloat const kAccountCellHeight = 60.0f;
static CGFloat const kAccountNetworkCellHeight = 50.0f;

@interface AccountsViewController ()
@property (nonatomic, assign) NSInteger expandedSection;
@property (nonatomic, strong) NSMutableDictionary *configuration;
@property (nonatomic, assign) BOOL canAddAccounts;
@property (nonatomic, assign) BOOL canRemoveAccounts;
@end

@implementation AccountsViewController

- (instancetype)initWithSession:(id<AlfrescoSession>)session
{
    self = [super initWithSession:session];
    if (self)
    {
        self.canAddAccounts = YES;
        self.canRemoveAccounts = YES;
        self.configuration = [NSMutableDictionary dictionary];
        
        [self registerForNotifications];
    }
    return self;
}

- (instancetype)initWithConfiguration:(NSDictionary *)configuration session:(id<AlfrescoSession>)session
{
    self = [self initWithSession:session];
    if (self)
    {
        self.configuration = (configuration) ? configuration.mutableCopy : [NSMutableDictionary dictionary];
        NSNumber *canAddAccounts = configuration[kAppConfigurationCanAddAccountsKey];
        self.canAddAccounts = (canAddAccounts) ? canAddAccounts.boolValue : YES;
        NSNumber *canRemoveAccounts = configuration[kAppConfigurationCanRemoveAccountsKey];
        self.canRemoveAccounts = (canRemoveAccounts) ? canRemoveAccounts.boolValue : YES;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"accounts.title", @"Accounts");
    self.tableView.emptyMessage = NSLocalizedString(@"accounts.empty", @"No Accounts");
    [self updateAccountList];
    
    if (self.canAddAccounts)
    {
        UIBarButtonItem *addAccount = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                    target:self
                                                                                    action:@selector(addAccount:)];
        self.navigationItem.rightBarButtonItem = addAccount;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[AnalyticsManager sharedManager] trackScreenWithName:kAnalyticsViewMenuAccounts];
}

- (void)updateAccountList
{
    self.tableViewData = [NSMutableArray array];
    NSArray *allAccounts = [[AccountManager sharedManager] allAccounts];
    
    for (UserAccount *account in allAccounts)
    {
        if (account.accountType == UserAccountTypeOnPremise)
        {
            [self.tableViewData addObject:@[account]];
        }
        else
        {
            NSMutableArray *accountData = [NSMutableArray array];
            [accountData addObject:account];
            [accountData addObjectsFromArray:account.accountNetworks];
            [self.tableViewData addObject:accountData];
        }
    }
    
    [self.tableView reloadData];
}

- (void)accountConfigurationUpdated:(NSNotification *)notification
{
    NSDictionary *configuration = notification.userInfo;
    [self configureViewForConfiguration:configuration];
}

- (void)configureViewForConfiguration:(NSDictionary *)configuration
{
    [self.configuration addEntriesFromDictionary:configuration];
    NSNumber *canAddAccounts = self.configuration[kAppConfigurationCanAddAccountsKey];
    self.canAddAccounts = (canAddAccounts) ? canAddAccounts.boolValue : YES;
    NSNumber *canRemoveAccounts = self.configuration[kAppConfigurationCanRemoveAccountsKey];
    self.canRemoveAccounts = (canRemoveAccounts) ? canRemoveAccounts.boolValue : YES;
    
    // Remove the add button if configuration to add accounts is set to NO
    if (!self.canAddAccounts)
    {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)registerForNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountAdded:) name:kAlfrescoAccountAddedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountRemoved:) name:kAlfrescoAccountRemovedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountListUpdated:) name:kAlfrescoAccountUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountListUpdated:) name:kAlfrescoAccountsListEmptyNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountConfigurationUpdated:) name:kAppConfigurationAccountsConfigurationUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mainMenuConfigurationChanged:) name:kAlfrescoConfigFileDidUpdateNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Notification Methods

- (void)sessionReceived:(NSNotification *)notification
{
    id<AlfrescoSession> session = notification.object;
    self.session = session;
}

- (void)accountAdded:(NSNotification *)notification
{
    [self updateAccountList];
}

- (void)accountRemoved:(NSNotification *)notification
{
    [self updateAccountList];
}

- (void)accountListUpdated:(NSNotification *)notification
{
    [self updateAccountList];
}

- (void)mainMenuConfigurationChanged:(NSNotification *)notification
{
    NSDictionary *configuration = notification.userInfo;
    [self configureViewForConfiguration:configuration];
}

#pragma mark - UIRefreshControl Functions

- (void)refreshTableView:(UIRefreshControl *)refreshControl
{
    [self showLoadingTextInRefreshControl:refreshControl];
    [self updateAccountList];
    [self hidePullToRefreshView];
}

#pragma mark - TableView Datasource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.tableViewData.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.tableViewData[section] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 0.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat cellHeight = kAccountCellHeight;
    
    if (indexPath.row >= kNetworksStartRowNumber)
    {
        cellHeight = kAccountNetworkCellHeight;
    }
    
    return cellHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"AccountCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    
    if (nil == cell)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    cell.accessoryView = [self createAccountSelectionButton];
    
    if (indexPath.row == kAccountRowNumber)
    {
        UserAccount *account = self.tableViewData[indexPath.section][indexPath.row];
        
        cell.textLabel.font = [UIFont systemFontOfSize:kDefaultFontSize];
        cell.textLabel.text = (account.accountDescription) ?: account.serverAddress;
        
        UIImage *accountTypeImage = [UIImage imageNamed:@"account-type-onpremise.png"];
        if (account.accountType == UserAccountTypeCloud)
        {
            accountTypeImage = [[UIImage imageNamed:@"account-type-cloud.png"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            if (account.oauthData && ![account.oauthData.apiKey isEqualToString:CLOUD_OAUTH_KEY])
            {
                cell.imageView.tintColor = [UIColor redColor];
            }
            else
            {
                cell.imageView.tintColor = [UIColor appTintColor];
            }
        }
        
        cell.imageView.image = accountTypeImage;
        
        if (account.accountType != UserAccountTypeCloud)
        {
            [self updateAccountSelectionButtonImageForCell:cell isSelected:account.isSelectedAccount];
        }
        else
        {
            cell.accessoryView.hidden = YES;
        }
    }
    else
    {
        NSString *networkIdentifier = self.tableViewData[indexPath.section][indexPath.row];
        
        cell.textLabel.font = [UIFont systemFontOfSize:[UIFont systemFontSize]];
        cell.textLabel.text = networkIdentifier;
        cell.imageView.image = [UIImage imageNamed:@"empty_icon.png"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UserAccount *account = self.tableViewData[indexPath.section][kAccountRowNumber];
        BOOL isSelectedNetwork = [account.selectedNetworkId isEqualToString:networkIdentifier];
        [self updateAccountSelectionButtonImageForCell:cell isSelected:isSelectedNetwork];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == kAccountRowNumber)
    {
        UserAccount *account = self.tableViewData[indexPath.section][indexPath.row];
        
        id viewController = nil;
        if ((account.accountType == UserAccountTypeCloud) && (account.accountNetworks.count == 0))
        {
            [self showHUD];
            [[LoginManager sharedManager] attemptLoginToAccount:account networkId:nil completionBlock:^(BOOL successful, id<AlfrescoSession> alfrescoSession, NSError *error) {
                [self hideHUD];
                if (successful)
                {
                    [[AccountManager sharedManager] selectAccount:account selectNetwork:account.accountNetworks.firstObject alfrescoSession:alfrescoSession];
                    [self updateAccountList];
                    
                    [[AnalyticsManager sharedManager] trackEventWithCategory:kAnalyticsEventCategorySession
                                                                      action:kAnalyticsEventActionSwitch
                                                                       label:kAnalyticsEventLabelCloud
                                                                       value:@1];
                }
            }];
        }
        else
        {
            // Only offer the AccountInfoViewController the session if it's the currently selected one
            viewController = [[AccountInfoViewController alloc] initWithAccount:account
                                                            accountActivityType:AccountActivityTypeEditAccount
                                                                  configuration:self.configuration
                                                                        session:account.isSelectedAccount ? self.session : nil];
        }
        
        if (viewController)
        {
            NavigationViewController *accountInfoNavigationController = [[NavigationViewController alloc] initWithRootViewController:viewController];
            accountInfoNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:accountInfoNavigationController animated:YES completion:nil];
        }
    }
    else
    {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.canRemoveAccounts == NO)
    {
        return NO;
    }
    
    if (self.tableViewData.count > 1)
    {
        if (indexPath.row != kAccountRowNumber)
        {
            return NO;
        }
        
        UserAccount *account = self.tableViewData[indexPath.section][indexPath.row];
        
        if (account.isSelectedAccount)
        {
            // Prevent deletion of active account.
            return NO;
        }
        else
        {
            return YES;
        }
    }
    
    return indexPath.row == kAccountRowNumber;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    AccountManager *accountManager = [AccountManager sharedManager];
    UserAccount *account = self.tableViewData[indexPath.section][indexPath.row];
    __weak typeof(self) weakSelf = self;
    
    void (^removeAccount)() = ^(){
	    [[RealmSyncManager sharedManager] disableSyncForAccount:account fromViewController:weakSelf cancelBlock:^{
	        [weakSelf performSelector:@selector(hideDeleteButton) withObject:nil afterDelay:0.05];
	    } completionBlock:^{
	        [accountManager removeAccount:account];
	        [weakSelf updateAccountList];
	    }];
    };
    
    // If this is the last paid account and passcode is enabled, authenticate via passcode before deleting the account.
    if ([[PreferenceManager sharedManager] shouldUsePasscodeLock] && [accountManager numberOfPaidAccounts] == 1 && account.isPaidAccount)
    {
        UINavigationController *navController = [PinViewController pinNavigationViewControllerWithFlow:PinFlowVerify completionBlock:^(PinFlowCompletionStatus status){
            switch (status)
            {
                case PinFlowCompletionStatusSuccess:
                    removeAccount();
                    break;
                    
                case PinFlowCompletionStatusCancel:
                    [tableView setEditing:NO animated:YES];
                    break;
                    
                case PinFlowCompletionStatusReset:
                    [SecurityManager resetWithType:ResetTypeEntireApp];
                    break;
                    
                default:
                    break;
            }
        }];
        [self presentViewController:navController animated:YES completion:nil];
        
        if ([TouchIDManager shouldUseTouchID])
        {
            [TouchIDManager evaluatePolicyWithCompletionBlock:^(BOOL success, NSError *authenticationError){
                if (success)
                {
                    [navController dismissViewControllerAnimated:NO completion:nil];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        removeAccount();
                    });
                }
            }];
        }
    }
    else
    {
        removeAccount();
    }
}

#pragma mark - Add Account

- (void)addAccount:(id)sender
{
    AccountTypeSelectionViewController *accountTypeController = [[AccountTypeSelectionViewController alloc] init];
    NavigationViewController *addAccountNavigationController = [[NavigationViewController alloc] initWithRootViewController:accountTypeController];
    addAccountNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:addAccountNavigationController animated:YES completion:nil];
}

#pragma mark - Private Methods

- (UIButton *)createAccountSelectionButton
{
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, kAccountSelectionButtonWidth, kAccountSelectionButtongHeight)];
    [button addTarget:self action:@selector(selectAccountButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)updateAccountSelectionButtonImageForCell:(UITableViewCell *)cell isSelected:(BOOL)isSelected
{
    UIImage *selectionImage = isSelected ? [UIImage imageNamed:@"green_selected_circle"] : [UIImage imageNamed:@"unselected_circle"];
    [(UIButton *)cell.accessoryView setBackgroundImage:selectionImage forState:UIControlStateNormal];
}

- (void)selectAccountButtonClicked:(UIButton *)sender
{
    UITableViewCell *selectedCell = (UITableViewCell *)sender.superview;
    
    BOOL foundAcccountCell = NO;
    while (!foundAcccountCell)
    {
        if (![selectedCell isKindOfClass:[UITableViewCell class]])
        {
            selectedCell = (UITableViewCell *)selectedCell.superview;
        }
        else
        {
            foundAcccountCell = YES;
        }
    }
    NSIndexPath *indexPathForSelectedCell = [self.tableView indexPathForCell:selectedCell];
    
    id item = self.tableViewData[indexPathForSelectedCell.section][indexPathForSelectedCell.row];
    UserAccount *account = nil;
    NSString *networkId = nil;
    
    if (indexPathForSelectedCell.row > kAccountRowNumber && [item isKindOfClass:[NSString class]])
    {
        account = self.tableViewData[indexPathForSelectedCell.section][kAccountRowNumber];
        networkId = (NSString *)item;
    }
    else
    {
        account = (UserAccount *)item;
    }
    
    if (account.accountType == UserAccountTypeOnPremise || networkId != nil)
    {
        [[LoginManager sharedManager] attemptLoginToAccount:account networkId:networkId completionBlock:^(BOOL successful, id<AlfrescoSession> alfrescoSession, NSError *error) {
            if (!successful)
            {
                if (account.password.length > 0)
                {
                    displayErrorMessage([ErrorDescriptions descriptionForError:error]);
                }
                else
                {
                    // Missing details - possibly first launch of an MDM-configured account
                    if ([account.username length] == 0)
                    {
                        displayWarningMessageWithTitle(NSLocalizedString(@"accountdetails.fields.accountSettings", @"Enter user name and password"), NSLocalizedString(@"accountdetails.header.authentication", "Account Details"));
                    }
                    else
                    {
                        displayWarningMessageWithTitle(NSLocalizedString(@"accountdetails.fields.confirmPassword", @"Confirm password"), NSLocalizedString(@"accountdetails.header.authentication", "Account Details"));
                    }
                }
            }
            else
            {
                [[AccountManager sharedManager] selectAccount:account selectNetwork:networkId alfrescoSession:alfrescoSession];
                [self.tableView reloadData];
                
                NSString *label = account.accountType == UserAccountTypeOnPremise ? kAnalyticsEventLabelOnPremise : kAnalyticsEventLabelCloud;
                [[AnalyticsManager sharedManager] trackEventWithCategory:kAnalyticsEventCategorySession
                                                                  action:kAnalyticsEventActionSwitch
                                                                   label:label
                                                                   value:@1];
                if (networkId)
                {
                    [[AnalyticsManager sharedManager] trackEventWithCategory:kAnalyticsEventCategorySession
                                                                      action:kAnalyticsEventActionSwitch
                                                                       label:kAnalyticsEventLabelNetwork
                                                                       value:@1];
                }
            }
        }];
    }
}

- (void)hideDeleteButton
{
    [self.tableView setEditing:NO animated:YES];
}

@end
