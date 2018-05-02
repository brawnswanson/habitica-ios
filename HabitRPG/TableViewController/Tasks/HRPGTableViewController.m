//
//  HRPGTableViewController.m
//  HabitRPG
//
//  Created by Phillip Thelen on 08/03/14.
//  Copyright © 2017 HabitRPG Inc. All rights reserved.
//

#import "HRPGTableViewController.h"
#import "HRPGFilterViewController.h"
#import "HRPGNavigationController.h"
#import "HRPGSearchDataManager.h"
#import "NSString+Emoji.h"
#import "UIColor+Habitica.h"
#import "Habitica-Swift.h"

@interface HRPGTableViewController ()<UISearchBarDelegate, UITableViewDragDelegate, UITableViewDropDelegate>
@property NSString *readableName;
@property NSString *typeName;
@property int extraCellSpacing;

@property(nonatomic, strong) UISearchBar *searchBar;

- (void)configureCell:(UITableViewCell *)cell
          atIndexPath:(NSIndexPath *)indexPath
        withAnimation:(BOOL)animate;

@property NSTimer *scrollTimer;
@property CGFloat autoScrollSpeed;
@property id movedTask;

@property NSMutableDictionary *heightAtIndexPath;

@end

@implementation HRPGTableViewController
BOOL editable;
NSIndexPath  *sourceIndexPath = nil;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.dataSource.tableView = self.tableView;
    
    
    UINib *nib = [UINib nibWithNibName:[self getCellNibName] bundle:nil];
    [[self tableView] registerNib:nib forCellReuseIdentifier:@"Cell"];
    
    self.coachMarks = @[ @"addTask", @"editTask", @"filterTask", @"reorderTask" ];

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 48)];
    self.searchBar.placeholder = NSLocalizedString(@"Search", nil);
    self.searchBar.delegate = self;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    self.tableView.tableHeaderView = self.searchBar;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeFilter:)
                                                 name:@"taskFilterChanged"
                                               object:nil];
    [self didChangeFilter:nil];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        // due to the way ipads are used we want to have a bit of extra spacing
        self.extraCellSpacing = 8;
    }
    self.dayStart = [[[HRPGManager sharedManager] getUser].preferences.dayStart integerValue];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 44;
    
    if (@available(iOS 11.0, *)) {
        self.tableView.dragDelegate = self;
        self.tableView.dropDelegate = self;
        [self.tableView setDragInteractionEnabled:YES];
    } else {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
                                                   initWithTarget:self action:@selector(longPressGestureRecognized:)];
        [self.tableView addGestureRecognizer:longPress];
    }
    
    self.heightAtIndexPath = [NSMutableDictionary new];
}

- (NSString *)getCellNibName {
    return nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (![HRPGSearchDataManager sharedManager].searchString ||
        [[HRPGSearchDataManager sharedManager].searchString isEqualToString:@""]) {
        self.searchBar.text = @"";
        [self.searchBar setShowsCancelButton:NO animated:YES];
    } else {
        self.searchBar.text = [HRPGSearchDataManager sharedManager].searchString;
    }

    [self.tableView reloadData];
    
    self.navigationItem.rightBarButtonItem.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Add %@", nil), self.readableName];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.scrollToTaskAfterLoading) {
        [self scrollToTaskWithId:self.scrollToTaskAfterLoading];
        self.scrollToTaskAfterLoading = nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *height = [self.heightAtIndexPath objectForKey:indexPath];
    if(height) {
        return height.floatValue;
    } else {
        return UITableViewAutomaticDimension;
    }
}

- (IBAction)longPressGestureRecognized:(id)sender {
    UILongPressGestureRecognizer *longPress = (UILongPressGestureRecognizer *)sender;
    UIGestureRecognizerState state = longPress.state;
    
    CGPoint location = [longPress locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    static UIView       *snapshot = nil;        ///< A snapshot of the row user is moving.
    switch (state) {
        case UIGestureRecognizerStateBegan: {
            if (indexPath) {
                sourceIndexPath = indexPath;
                
                UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                
                snapshot = [self customSnapshoFromView:cell];
                
                __block CGPoint center = cell.center;
                snapshot.center = center;
                snapshot.alpha = 0.0;
                [self.tableView addSubview:snapshot];
                [UIView animateWithDuration:0.3 delay:0.0 usingSpringWithDamping:0.25 initialSpringVelocity:0.75 options:0 animations:^{
                    center.y = location.y;
                    snapshot.center = center;
                    snapshot.transform = CGAffineTransformMakeScale(1.075, 1.075);
                    snapshot.alpha = 0.98;
                    cell.alpha = 0.0;
                } completion:^(BOOL finished) {
                    cell.hidden = YES;
                }];
            }
            break;
        }
            
        case UIGestureRecognizerStateChanged: {
            CGPoint center = snapshot.center;
            center.y = location.y;
            snapshot.center = center;
            
            if (indexPath && ![indexPath isEqual:sourceIndexPath]) {
                self.dataSource.userDrivenDataUpdate = YES;
                id sourceTask = [self.dataSource taskAt:sourceIndexPath];
                id task = [self.dataSource taskAt:indexPath];
                NSInteger sourceOrder = [sourceTask integerForKey:@"order"];
                [sourceTask setInteger:[task integerForKey:@"order"] forKey:@"order"];
                [task setInteger:sourceOrder forKey:@"order"];

                NSError *error;
                [self.managedObjectContext save:&error];
                
                [self.tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:indexPath];
                sourceIndexPath = indexPath;
                self.dataSource.userDrivenDataUpdate = NO;
            }
            
            CGFloat positionInTableView = [self.view convertPoint:center fromView:snapshot.superview].y - self.tableView.contentOffset.y;
            CGFloat bottomThreshhold = self.tableView.frame.size.height - 120;
            CGFloat topThreshhold = self.tableView.frame.origin.y + 120;
            if (positionInTableView > bottomThreshhold) {
                if (self.autoScrollSpeed == 0) {
                    [self startAutoScrolling];
                }
                self.autoScrollSpeed = ((positionInTableView-bottomThreshhold)/120) * 10;
                
            } else if (positionInTableView < topThreshhold) {
                if (self.autoScrollSpeed == 0) {
                    [self startAutoScrolling];
                }
                self.autoScrollSpeed = ((positionInTableView-topThreshhold)/120) * 10;
            } else {
                self.autoScrollSpeed = 0;
            }
            
            break;
        }
            
        default: {
            id task = [self.dataSource taskAt:sourceIndexPath];
            [self.dataSource moveTaskWithTask:task toPosition:[task valueForKey:@"order"] completion:^{
                
            }];
            
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:sourceIndexPath];
            cell.alpha = 0.0;
            
            [UIView animateWithDuration:2.0 delay:0.0 usingSpringWithDamping:0.5 initialSpringVelocity:1.0 options:0 animations:^{
                
                snapshot.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) {
                
                
            }];
            
            break;
        }
    }
}

- (void)refresh {
    __weak HRPGTableViewController *weakSelf = self;
    [self.dataSource retrieveDataWithCompleted:^{
        [weakSelf.refreshControl endRefreshing];
    }];
}

- (NSPredicate *)getPredicate {
    NSMutableArray *predicateArray = [[NSMutableArray alloc] initWithCapacity:3];
    MainTabBarController *tabBarController = (MainTabBarController *)self.tabBarController;

    [predicateArray addObjectsFromArray:[Task predicatesForTaskType:self.typeName
                                                     withFilterType:self.filterType withOffset:self.dayStart]];

    if ([tabBarController.selectedTags count] > 0) {
        [predicateArray
            addObject:[NSPredicate
                          predicateWithFormat:@"SUBQUERY(realmTags, $tag, $tag.id IN %@).@count = %d",
                                              tabBarController.selectedTags,
                                              [tabBarController.selectedTags count]]];
    }

    if ([HRPGSearchDataManager sharedManager].searchString) {
        [predicateArray
            addObject:[NSPredicate
                          predicateWithFormat:@"(text CONTAINS[cd] %@) OR (notes CONTAINS[cd] %@)",
                                              [HRPGSearchDataManager sharedManager].searchString,
                                              [HRPGSearchDataManager sharedManager].searchString]];
    }

    return [NSCompoundPredicate andPredicateWithSubpredicates:predicateArray];
}

- (void)didChangeFilter:(NSNotification *)notification {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.filterType =
        [defaults integerForKey:[NSString stringWithFormat:@"%@Filter", self.typeName]];

    self.dataSource.predicate = [self getPredicate];
    [self.tableView reloadData];

    NSInteger filterCount = 0;
    if (self.filterType != 0) {
        filterCount++;
    }
    MainTabBarController *tabBarController = (MainTabBarController *)self.tabBarController;
    filterCount += tabBarController.selectedTags.count;

    if (filterCount == 0) {
        self.navigationItem.leftBarButtonItem.title = NSLocalizedString(@"Filter", nil);
    } else if (filterCount == 1) {
        self.navigationItem.leftBarButtonItem.title = NSLocalizedString(@"1 Filter", nil);
    } else {
        self.navigationItem.leftBarButtonItem.title =
            [NSString stringWithFormat:NSLocalizedString(@"%ld Filters", @"more than one filter"),
                                       (long)filterCount];
    }
}

- (CGRect)getFrameForCoachmark:(NSString *)coachMarkIdentifier {
    if ([coachMarkIdentifier isEqualToString:@"addTask"]) {
        return CGRectMake(self.view.frame.size.width - 47, 19, 44, 44);
    } else if ([coachMarkIdentifier isEqualToString:@"editTask"]) {
        if ([self.tableView numberOfRowsInSection:0] > 0) {
            NSArray *visibleCells = [self.tableView indexPathsForVisibleRows];

            UITableViewCell *cell;
            for (NSIndexPath *indexPath in visibleCells) {
                cell = [self.tableView cellForRowAtIndexPath:indexPath];
                CGRect frame = [self.tableView
                    convertRect:cell.frame
                         toView:self.parentViewController.parentViewController.view];
                if (frame.origin.y >= self.tableView.contentInset.top) {
                    return frame;
                }
            }
            return [self.tableView convertRect:cell.frame
                                        toView:self.parentViewController.parentViewController.view];
        }
    } else if ([coachMarkIdentifier isEqualToString:@"filterTask"]) {
        NSInteger width = [self.navigationItem.leftBarButtonItem.title
                              boundingRectWithSize:CGSizeMake(MAXFLOAT, MAXFLOAT)
                                           options:NSStringDrawingUsesLineFragmentOrigin |
                                                   NSStringDrawingUsesFontLeading
                                        attributes:@{
                                            NSFontAttributeName : [UIFont systemFontOfSize:17.0]
                                        }
                                           context:nil]
                              .size.width;
        return CGRectMake(5, 20, width + 6, 44);
    } else if ([coachMarkIdentifier isEqualToString:@"reorderTask"]) {
        if ([self.tableView numberOfRowsInSection:0] > 0) {
            NSArray *visibleCells = [self.tableView indexPathsForVisibleRows];
            
            UITableViewCell *cell;
            for (NSIndexPath *indexPath in visibleCells) {
                cell = [self.tableView cellForRowAtIndexPath:indexPath];
                CGRect frame = [self.tableView
                                convertRect:cell.frame
                                toView:self.parentViewController.parentViewController.view];
                if (frame.origin.y >= self.tableView.contentInset.top) {
                    return frame;
                }
            }
            return [self.tableView convertRect:cell.frame
                                        toView:self.parentViewController.parentViewController.view];
        }
    }
    return CGRectZero;
}

- (NSDictionary *)getDefinitonForTutorial:(NSString *)tutorialIdentifier {
    if ([tutorialIdentifier isEqualToString:@"addTask"]) {
        return @{ @"text" : NSLocalizedString(@"Tap to add a new task.", nil) };
    } else if ([tutorialIdentifier isEqualToString:@"editTask"]) {
        return @{
            @"text" : NSLocalizedString(
                @"Tap a task to edit it and add reminders. Swipe left to delete it.", nil)
        };
    } else if ([tutorialIdentifier isEqualToString:@"filterTask"]) {
        return @{ @"text" : NSLocalizedString(@"Tap to filter tasks.", nil) };
    } else if ([tutorialIdentifier isEqualToString:@"reorderTask"]) {
        return @{@"text" : NSLocalizedString(@"Hold down on a task to drag it around.", nil)};
    }
    return nil;
}

#pragma mark - Table view data source

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self.dataSource selectRowAtIndexPath:indexPath];
    [self performSegueWithIdentifier:@"FormSegue" sender:self];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (IBAction)unwindToList:(UIStoryboardSegue *)segue {
    if ([segue.identifier isEqualToString:@"UnwindTagSegue"]) {
        HRPGFilterViewController *tagViewController = segue.sourceViewController;
        MainTabBarController *tabBarController = (MainTabBarController *)self.tabBarController;
        tabBarController.selectedTags = tagViewController.selectedTags;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"taskFilterChanged" object:nil];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    if ([self.tableView respondsToSelector:@selector(setSeparatorInset:)]) {
        [self.tableView setSeparatorInset:UIEdgeInsetsZero];
    }

    if ([self.tableView respondsToSelector:@selector(setLayoutMargins:)]) {
        [self.tableView setLayoutMargins:UIEdgeInsetsZero];
    }
}

- (void)configureCell:(UITableViewCell *)cell
          atIndexPath:(NSIndexPath *)indexPath
        withAnimation:(BOOL)animate {
}

- (UIView *)viewWithIcon:(UIImage *)image {
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeCenter;
    return imageView;
}

#pragma mark - Search
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [HRPGSearchDataManager sharedManager].searchString = searchText;

    if ([[HRPGSearchDataManager sharedManager].searchString isEqualToString:@""]) {
        [HRPGSearchDataManager sharedManager].searchString = nil;
    }

    self.dataSource.predicate = [self getPredicate];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self.searchBar resignFirstResponder];
    [self.searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    self.searchBar.text = @"";
    [searchBar setShowsCancelButton:NO animated:YES];

    [HRPGSearchDataManager sharedManager].searchString = nil;

    [searchBar resignFirstResponder];

    [self.tableView reloadData];
}

- (void)scrollToTaskWithId:(NSString *)taskID {
    NSInteger index = 0;
    NSIndexPath *indexPath;
    for (Task *task in self.dataSource.tasks) {
        if ([task.id isEqualToString:taskID]) {
            indexPath = [NSIndexPath indexPathForItem:index inSection:0];
            break;
        }
        index++;
    }
    if (indexPath) {
        [self.tableView scrollToRowAtIndexPath:indexPath
                              atScrollPosition:UITableViewScrollPositionMiddle
                                      animated:YES];
    }
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"FormSegue"]) {
        TaskFormVisualEffectsModalViewController *destViewController = segue.destinationViewController;
        [destViewController setTaskTypeStringWithType:self.typeName];
        if (self.dataSource.taskToEdit) {
            id task = self.dataSource.taskToEdit;
            self.dataSource.taskToEdit = nil;
            destViewController.taskId = [task valueForKey:@"id"];
            destViewController.isCreating = NO;
        } else {
            destViewController.isCreating = YES;
        }
    } else if ([segue.identifier isEqualToString:@"FilterSegue"]) {
        MainTabBarController *tabBarController = (MainTabBarController *)self.tabBarController;
        HRPGNavigationController *navigationController = segue.destinationViewController;
        navigationController.sourceViewController = self;
        HRPGFilterViewController *filterController =
            (HRPGFilterViewController *)navigationController.topViewController;
        filterController.selectedTags = [tabBarController.selectedTags mutableCopy];
        filterController.taskType = self.typeName;
    }
}

- (UIView *)customSnapshoFromView:(UIView *)inputView {
    
    // Make an image from the input view.
    UIGraphicsBeginImageContextWithOptions(inputView.bounds.size, NO, 0);
    [inputView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // Create an image view.
    UIView *snapshot = [[UIImageView alloc] initWithImage:image];
    snapshot.layer.masksToBounds = NO;
    snapshot.layer.cornerRadius = 0.0;
    snapshot.layer.shadowOffset = CGSizeMake(-5.0, 0.0);
    snapshot.layer.shadowRadius = 5.0;
    snapshot.layer.shadowOpacity = 0.4;
    
    return snapshot;
}

- (void) startAutoScrolling {
    if (self.scrollTimer == nil) {
        self.scrollTimer = [NSTimer scheduledTimerWithTimeInterval:(0.03)
                                                          target:self selector:@selector(autoscrollTimer) userInfo:nil repeats:YES];
    }
}

- (void) autoscrollTimer {
    if (self.autoScrollSpeed == 0) {
        [self.scrollTimer invalidate];
        self.scrollTimer = nil;
    } else {
        CGPoint scrollPoint = CGPointMake(self.tableView.contentOffset.x, self.tableView.contentOffset.y+self.autoScrollSpeed);
        if (scrollPoint.y > -self.tableView.contentInset.top && scrollPoint.y < (self.tableView.contentSize.height - self.tableView.frame.size.height)) {
            [self.tableView setContentOffset:scrollPoint animated:NO];
        }
    }
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath NS_AVAILABLE_IOS(11.0) {
    self.movedTask = [self.dataSource taskAt:indexPath];
    NSString *taskName = [self.movedTask valueForKey:@"text"];
    sourceIndexPath = indexPath;
    
    NSData *data = [taskName dataUsingEncoding:NSUTF16StringEncoding];
    NSItemProvider *itemProvider = [[NSItemProvider alloc] init];
    
    [itemProvider registerDataRepresentationForTypeIdentifier:[NSString stringWithString:kUTTypeUTF16PlainText] visibility:NSItemProviderRepresentationVisibilityOwnProcess loadHandler:^NSProgress * _Nullable(void (^ _Nonnull completionHandler)(NSData * _Nullable, NSError * _Nullable)) {
        completionHandler(data, nil);
        return nil;
    }];
    self.dataSource.userDrivenDataUpdate = YES;
    return @[[[UIDragItem alloc] initWithItemProvider: itemProvider]];
}

- (BOOL)tableView:(UITableView *)tableView canHandleDropSession:(id<UIDropSession>)session NS_AVAILABLE_IOS(11.0) {
    return YES;
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath NS_AVAILABLE_IOS(11.0) {
    //[self.dataSource fixTaskOrderWithMovedTask:self.movedTask toPosition:destinationIndexPath.item];
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator NS_AVAILABLE_IOS(11.0) {
    id order = [self.movedTask valueForKey:@"order"];
    NSIndexPath *sourceIndexPath = [NSIndexPath indexPathForRow:[order integerValue] inSection:0];
    [self.dataSource fixTaskOrderWithMovedTask:self.movedTask toPosition:coordinator.destinationIndexPath.item];
    [self.tableView moveRowAtIndexPath:sourceIndexPath toIndexPath:coordinator.destinationIndexPath];
    [self.dataSource moveTaskWithTask:self.movedTask toPosition:coordinator.destinationIndexPath.item completion:^{
        self.dataSource.userDrivenDataUpdate = NO;
    }];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    
    [self.dataSource moveTaskWithTask:self.movedTask toPosition:destinationIndexPath.item completion:^{
        self.dataSource.userDrivenDataUpdate = NO;
    }];
}

@end
