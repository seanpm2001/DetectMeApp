//
//  GalleryViewController.m
//  DetecTube
//
//  Created by Josep Marc Mingot Hidalgo on 16/09/13.
//  Copyright (c) 2013 Josep Marc Mingot Hidalgo. All rights reserved.
//

#import "GalleryViewController.h"
#import "DetectorFetcher.h"
#import "DetectorCell.h"
#import "User.h"
#import "Detector+Server.h"
#import "MultipleDetector.h"
#import "ExecuteDetectorViewController.h"
#import "ManagedDocumentHelper.h"
#import "ConstantsServer.h"
#import "ShareDetector.h"
#import "AnnotatedImage.h"
#import "UIViewController+ShowAlert.h"
#import "MultipleDetector+Create.h"



@interface GalleryViewController()
{
    UIRefreshControl *_refreshControl;
    NSMutableArray *_selectedDetectors;
}
@end


@implementation GalleryViewController

#pragma mark -  
#pragma mark Initialization

- (void) initializeRefreshControl
{
    if([self.filter isEqualToString:FILTER_SERVER]){
        self.collectionView.alwaysBounceVertical = YES;
        
        _refreshControl = [[UIRefreshControl alloc] init];
        [_refreshControl addTarget:self action:@selector(refreshAction:) forControlEvents:UIControlEventValueChanged];
        [self.collectionView addSubview:_refreshControl];
    }
}

- (void) initializeDataBase
{
    if(!self.detectorDatabase){
        self.detectorDatabase = [ManagedDocumentHelper sharedDatabaseUsingBlock:^(UIManagedDocument *document){}];
    }
}

- (void) applyFilter
{
    
    if([self.filter isEqualToString:FILTER_SINGLE]){
        [self fetchSingle];
        
        self.title = @"My Single";
        
    }else if([self.filter isEqualToString:FILTER_MULTIPLE]){
        [self fetchMultiples];
        
        // show add and back button
        self.addButton.enabled = YES;
        self.navigationItem.hidesBackButton = NO;
        
        self.title = @"My Multiple";
        
    }else if([self.filter isEqualToString:FILTER_SERVER]){
        [self fetchServer];
        [self.navigationItem setRightBarButtonItem:nil animated:NO];
        
        self.title = @"Server";
        
    }else if([self.filter isEqualToString:FILTER_SELECTION]){
        [self fetchAll];
        self.title = @"Select Detectors!";
        
        // hide add and back button
        self.addButton.enabled = NO;
        self.navigationItem.hidesBackButton = YES;
        
        _selectedDetectors = [[NSMutableArray alloc] init];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
//    self.debug = YES;
    
    // Remove extra top margin
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    [self initializeDataBase];
    [self initializeRefreshControl];
    
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyFilter];
}



#pragma mark -
#pragma mark IBActions


- (IBAction)refreshAction:(id)sender
{
    // Update from server
    [self fetchDetectorsFromServerIntoDocument:self.detectorDatabase];
    [self fetchServer];
    
    // Try to send all the detectors/images/ratings that have not been send
    [self persistentSent:@"Detector"];
    [self persistentSent:@"AnnotatedImage"];
    [self persistentSent:@"Rating"];
    [self unrelatedImages];
    
    NSLog(@"Refreshing...");
    [_refreshControl endRefreshing];
}



- (IBAction)addAction:(id)sender
{
    if([self.filter isEqualToString:FILTER_MULTIPLE]){
        
        self.filter = FILTER_SELECTION;
        [self applyFilter];
        
        //[self performSegueWithIdentifier:@"AddMultipleDetector" sender:self];
    
    }else{
        [self performSegueWithIdentifier:@"AddSingleDetector" sender:self];
    }
}

- (IBAction)doneSelectingAction:(id)sender
{
    if(_selectedDetectors.count<2) [self showAlertWithTitle:@"Error" andDescription:@"You need at least 2 detectors."];
    else{
        [MultipleDetector multipleDetectorWithName:@"mulitple"
                                      forDetectors:_selectedDetectors
                            inManagedObjectContext:_detectorDatabase.managedObjectContext];
        
        
        // Restore previous
        self.filter = FILTER_MULTIPLE;
        [self applyFilter];
    }
}

- (IBAction)cancelSelectingAction:(id)sender
{
    // Restore previous
    self.filter = FILTER_MULTIPLE;
    [self applyFilter];
}


#pragma mark -
#pragma mark UISearchDelegate

- (void) searchBarTextDidBeginEditing:(UISearchBar *) searchBar
{
    searchBar.showsCancelButton = YES;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    
    // The user clicked the [X] button or otherwise cleared the text.
    if([searchText length] == 0) {
        [self applyFilter];

    }else
        [self fetchResultsForPredicate:[NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR targetClass CONTAINS[cd] %@", searchText, searchText]];

}


- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    searchBar.showsCancelButton = NO;
    [searchBar resignFirstResponder];
    [self.view endEditing:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    searchBar.showsCancelButton = NO;
    [searchBar resignFirstResponder];
    [self.view endEditing:YES];
}

#pragma mark -
#pragma mark UICollectionView DataSource & Delegate

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    DetectorCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"DetectorCell" forIndexPath:indexPath];
    id element = [self.fetchedResultsController objectAtIndexPath:indexPath];
    if([element isKindOfClass:[Detector class]]){
        Detector *detector = (Detector *)element;
        [cell.label setText:[NSString stringWithFormat:@"%@-%@\n %@",detector.name,
                                                                     detector.serverDatabaseID,
                                                                     detector.user.username]];
        cell.imageView.image = [UIImage imageWithData:detector.image];
        
    }else if([element isKindOfClass:[MultipleDetector class]]){
        MultipleDetector *multipleDetector = (MultipleDetector *) element;
        cell.imageView.image = [UIImage imageWithData:multipleDetector.image];
        cell.label.text = [NSString stringWithFormat:@"%@ %@", multipleDetector.name, [multipleDetector.uuid substringToIndex:3]];
        
        // hack to avoid keeping the cell selected after creating a new multiple detector
        [self deselectCell:cell];
    }
    
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if([self.filter isEqualToString:FILTER_SELECTION]){
        
        DetectorCell *imageCell = (DetectorCell *)[collectionView cellForItemAtIndexPath:indexPath];
        Detector *detector = [self.fetchedResultsController objectAtIndexPath:indexPath];
        
        if([_selectedDetectors containsObject:detector]){
            [self deselectCell:imageCell];
            [_selectedDetectors removeObject:detector];
        }else{
            [self selectCell:imageCell];
            [_selectedDetectors addObject:detector];
        }
        
    }else{
        
        id element = [self.fetchedResultsController objectAtIndexPath:indexPath];
        
        if([element isKindOfClass:[Detector class]]){
            [self performSegueWithIdentifier: @"ShowDetailSimple" sender: self];
            
        } else if ([element isKindOfClass:[MultipleDetector class]]){
            [self performSegueWithIdentifier:@"ShowDetailMultiple" sender:self];
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    // TODO: Deselect item
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    // Footer when no images
    UICollectionReusableView *reusableView;
    
    if (kind == UICollectionElementKindSectionFooter) {
        UICollectionReusableView *footerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"CollectionFooterView" forIndexPath:indexPath];
        

        if(self.fetchedResultsController.fetchedObjects.count>0){
            footerView.hidden = YES;
        }else{
            footerView.hidden = NO;
            if([self.filter isEqualToString:FILTER_SERVER]){
                
                // Different label to show
                UILabel *footerLabel = [footerView.subviews lastObject];
                footerLabel.text = @"Scroll to refresh \n from the server.";
            }
        }
        
        reusableView = footerView;
        
    }else if(kind == UICollectionElementKindSectionHeader){
        UICollectionReusableView *headerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"CollectionHeaderView" forIndexPath:indexPath];
        
        reusableView = headerView;
    }
    
    return reusableView;
}

// Layout
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGSize retval = CGSizeMake(100, 100);
    return retval;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    CGSize headerSize;
    
    if([self.filter isEqualToString:FILTER_SELECTION]){
        headerSize = CGSizeMake(collectionView.frame.size.width, 120);
        
    }else{
        headerSize = CGSizeMake(0, 0);
    }
    
    return headerSize;
}


//- (UIEdgeInsets)collectionView: (UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
//{
//    return UIEdgeInsetsMake(0,0,0,0);//(50, 10, 50, 10);
//}



#pragma mark -
#pragma mark Segue

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    NSIndexPath *indexPath = [[self.collectionView indexPathsForSelectedItems] lastObject];
    
    if ([[segue identifier] isEqualToString:@"ExecuteDetector"]) {
        Detector *detector = [self.fetchedResultsController objectAtIndexPath:indexPath];
        NSArray *detectors = [NSArray arrayWithObject:detector];
        [(ExecuteDetectorViewController *)segue.destinationViewController setDetectors:detectors];
        
    }else if([[segue identifier] isEqualToString:@"ShowDetailSimple"]){
        Detector *detector = [self.fetchedResultsController objectAtIndexPath:indexPath];
        DetailViewController *detailVC = (DetailViewController *) segue.destinationViewController;
        detailVC.hidesBottomBarWhenPushed = YES;
        detailVC.detector = detector;
        
    }else if ([[segue identifier] isEqualToString:@"ShowDetailMultiple"]){
        MultipleDetector *multipleDetector = [self.fetchedResultsController objectAtIndexPath:indexPath];
        DetailMultipleViewController *detailMultipleVC = (DetailMultipleViewController *) segue.destinationViewController;
        detailMultipleVC.multipleDetector = multipleDetector;
        
    }else if([[segue identifier] isEqualToString:@"AddSingleDetector"]){
        // Set the title for the back button of the next controller
        self.title = @"Dismiss";
    }
}


#pragma mark -
#pragma mark Private methods

- (void) fetchResultsForPredicate:(NSPredicate *)predicate
{
    // Everything that happens in this context is automatically hooked to the table
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Detector"];
    if(predicate) request.predicate = predicate;
    request.sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
    
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                        managedObjectContext:self.detectorDatabase.managedObjectContext
                                                                          sectionNameKeyPath:nil
                                                                                   cacheName:nil];
    [_refreshControl endRefreshing];
}

- (void) fetchSingle
{
    NSString *currentUsername = [[NSUserDefaults standardUserDefaults] stringForKey:USER_DEFAULTS_USERNAME];
    [self fetchResultsForPredicate:[NSPredicate predicateWithFormat:@"user.username == %@", currentUsername]];
}

- (void) fetchServer
{
    [self fetchResultsForPredicate:[NSPredicate predicateWithFormat:@"isPublic == YES"]];
}

- (void) fetchAll
{
    [self fetchResultsForPredicate:nil];
}

- (void) fetchMultiples
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"MultipleDetector"];
    request.sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]];
    self.fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:request
                                                                        managedObjectContext:self.detectorDatabase.managedObjectContext
                                                                          sectionNameKeyPath:nil
                                                                                   cacheName:nil];
}


- (void) fetchDetectorsFromServerIntoDocument:(UIManagedDocument *) document
{
    // Populate the table if it was not.
    // |document| as an argument for thread safe: someone could change the propertie in parallel
    dispatch_queue_t fetchQ = dispatch_queue_create("Detectors Fetcher", NULL);
    dispatch_async(fetchQ, ^{
        NSArray *detectors = [DetectorFetcher fetchDetectorsSync];
        [document.managedObjectContext performBlock:^{
            if (detectors.count>0) {
                //[Detector removePublicDetectorsInManagedObjectContext:document.managedObjectContext];
            }
            for(NSDictionary *detectorInfo in detectors){
                //start creating objects in document's context
                [Detector detectorWithDictionaryInfo:detectorInfo inManagedObjectContext:document.managedObjectContext];
            }
        
            
            // when finished, present them on the screen
            [self performSelectorOnMainThread:@selector(applyFilter) withObject:nil waitUntilDone:NO];
        }];
    });
}

- (void) persistentSent:(NSString *)modelName
{
    NSError *error;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:modelName];
    request.predicate = [NSPredicate predicateWithFormat:@"isSent == NO"];
    NSArray *matches = [self.detectorDatabase.managedObjectContext executeFetchRequest:request error:&error];
    
    NSLog(@"Found %lu for %@", (unsigned long)matches.count, modelName);
    
    for(id element in matches){
        ShareDetector *sh = [[ShareDetector alloc] init];
        if([modelName isEqualToString:@"Detector"]){
            Detector *detector = (Detector *)element;
            [sh shareDetector:detector toUpdate:detector.serverDatabaseID ? YES:NO];
            
        }else if([modelName isEqualToString:@"AnnotatedImage"]){
            [sh shareAnnotatedImage:(AnnotatedImage *)element];
            
        }else if([modelName isEqualToString:@"Rating"]){
            [sh shareRating:(Rating *) element];
        }
    }
}

- (void) unrelatedImages
{
    NSError *error;
    
    // get chair
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Detector"];
    request.predicate = [NSPredicate predicateWithFormat:@"serverDatabaseID == 26"];
    NSArray *matches = [self.detectorDatabase.managedObjectContext executeFetchRequest:request error:&error];
    Detector *detector = [matches firstObject];
    
    
    request = [NSFetchRequest fetchRequestWithEntityName:@"AnnotatedImage"];
    request.predicate = [NSPredicate predicateWithFormat:@"detector == nil"];
    matches = [self.detectorDatabase.managedObjectContext executeFetchRequest:request error:&error];
    
    for(AnnotatedImage *ai in matches)
        ai.detector = detector;
    
    NSLog(@"Number of unrelated images: %lu", (unsigned long)matches.count);
    
}


- (void) selectCell:(DetectorCell *)cell
{
    //using defautl iOS 7 blue color
    [cell.imageView.layer setBorderColor: [[UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0] CGColor]];
    [cell.imageView.layer setBorderWidth: 4.0];
    cell.imageView.alpha = 0.5;
}

- (void) deselectCell:(DetectorCell *)cell
{
    [cell.imageView.layer setBorderWidth: 0.0];
    cell.imageView.alpha = 1;
}

- (void)viewDidUnload
{
    [self setCollectionView:nil];
    [super viewDidUnload];
}

@end
