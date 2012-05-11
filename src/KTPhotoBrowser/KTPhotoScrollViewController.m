//
//  KTPhotoScrollViewController.m
//  KTPhotoBrowser
//
//  Created by Kirby Turner on 2/4/10.
//  Copyright 2010 White Peak Software Inc. All rights reserved.
//

#import "KTPhotoScrollViewController.h"
#import "KTPhotoBrowserDataSource.h"
#import "KTPhotoBrowserGlobal.h"
#import "KTPhotoView.h"

const CGFloat ktkDefaultPortraitToolbarHeight   = 44;
const CGFloat ktkDefaultLandscapeToolbarHeight  = 33;
const CGFloat ktkDefaultToolbarHeight = 44;

#define BUTTON_DELETEPHOTO 0
#define BUTTON_CANCEL 1

@interface KTPhotoScrollViewController (KTPrivate)
- (void)setCurrentIndex:(NSInteger)newIndex;
- (void)toggleChrome:(BOOL)hide;
- (void)startChromeDisplayTimer;
- (void)cancelChromeDisplayTimer;
- (void)hideChrome;
- (void)showChrome;
- (void)swapCurrentAndNextPhotos;
- (void)nextPhoto;
- (void)previousPhoto;
- (void)toggleNavButtons;
- (CGRect)frameForPagingScrollView;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
- (void)loadPhoto:(NSInteger)index;
- (void)unloadPhoto:(NSInteger)index;
- (void)trashPhoto;
- (void)exportPhoto;
- (void)layoutScrollViewSubviews;
- (void)updateToolbarWithOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (void)startCaptionDisplayTimer;
- (void)cancelCaptionDisplayTimer;
@end

@implementation KTPhotoScrollViewController

@synthesize statusBarStyle = statusBarStyle_;
@synthesize statusbarHidden = statusbarHidden_;


- (void)dealloc 
{
   [nextButton_ release], nextButton_ = nil;
   [previousButton_ release], previousButton_ = nil;
   [scrollView_ release], scrollView_ = nil;
   [toolbar_ release], toolbar_ = nil;
   [photoViews_ release], photoViews_ = nil;
  
   [dataSource_ release], dataSource_ = nil;  
   
   [super dealloc];
}

- (id)initWithDataSource:(id <KTPhotoBrowserDataSource>)dataSource andStartWithPhotoAtIndex:(NSUInteger)index fullScreen:(BOOL)useFullScreen
{
   if ((self = [super init])) {
     startWithIndex_ = index;
     dataSource_ = [dataSource retain];
       useFullScreen_ = useFullScreen;
     // Make sure to set wantsFullScreenLayout or the photo
     // will not display behind the status bar.
     [self setWantsFullScreenLayout:useFullScreen];

     BOOL isStatusbarHidden = [[UIApplication sharedApplication] isStatusBarHidden];
     [self setStatusbarHidden:isStatusbarHidden];
     
     self.hidesBottomBarWhenPushed = YES;
   }
   return self;
}

- (void)loadView 
{
   [super loadView];
   
   CGRect scrollFrame = [self frameForPagingScrollView];
   UIScrollView *newView = [[UIScrollView alloc] initWithFrame:scrollFrame];
   [newView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
   [newView setDelegate:self];
   
   UIColor *backgroundColor = [dataSource_ respondsToSelector:@selector(imageBackgroundColor)] ?
                                [dataSource_ imageBackgroundColor] : [UIColor blackColor];  
   [newView setBackgroundColor:backgroundColor];
   [newView setAutoresizesSubviews:YES];
   [newView setPagingEnabled:YES];
   [newView setShowsVerticalScrollIndicator:NO];
   [newView setShowsHorizontalScrollIndicator:NO];
   
   [[self view] addSubview:newView];
   
   scrollView_ = [newView retain];
   
   [newView release];
   
   nextButton_ = [[UIBarButtonItem alloc] 
                  initWithImage:KTLoadImageFromBundle(@"nextIcon.png")
                  style:UIBarButtonItemStylePlain
                  target:self
                  action:@selector(nextPhoto)];
   
   previousButton_ = [[UIBarButtonItem alloc] 
                      initWithImage:KTLoadImageFromBundle(@"previousIcon.png")
                      style:UIBarButtonItemStylePlain
                      target:self
                      action:@selector(previousPhoto)];
   
   UIBarButtonItem *trashButton = nil;
   if ([dataSource_ respondsToSelector:@selector(deleteImageAtIndex:)]) {
     trashButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                                 target:self
                                                                 action:@selector(trashPhoto)];
   }
   
   UIBarButtonItem *exportButton = nil;
   if ([dataSource_ respondsToSelector:@selector(exportImageAtIndex:)])
   {
      exportButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction 
                                                                   target:self
                                                                   action:@selector(exportPhoto)];
   }
   

   UIBarItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                    target:nil 
                                                                    action:nil];
   
   NSMutableArray *toolbarItems = [[NSMutableArray alloc] initWithCapacity:7];
   
   if (exportButton) [toolbarItems addObject:exportButton];
   [toolbarItems addObject:space];
   [toolbarItems addObject:previousButton_];
   [toolbarItems addObject:space];
   [toolbarItems addObject:nextButton_];
   [toolbarItems addObject:space];
   if (trashButton) [toolbarItems addObject:trashButton];
   
   CGRect screenFrame = [[UIScreen mainScreen] bounds];
   CGRect toolbarFrame = CGRectMake(0, 
                                    screenFrame.size.height - ktkDefaultToolbarHeight, 
                                    screenFrame.size.width, 
                                    ktkDefaultToolbarHeight);
   toolbar_ = [[UIToolbar alloc] initWithFrame:toolbarFrame];
   [toolbar_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin];
   [toolbar_ setBarStyle:UIBarStyleBlackTranslucent];
   [toolbar_ setItems:toolbarItems];
   [[self view] addSubview:toolbar_];
   
   if (trashButton) [trashButton release];
   if (exportButton) [exportButton release];
   [toolbarItems release];
   [space release];
}

- (void)setTitleWithCurrentPhotoIndex 
{
   NSString *formatString = NSLocalizedString(@"%1$i of %2$i", @"Picture X out of Y total.");
   NSString *title = [NSString stringWithFormat:formatString, currentIndex_ + 1, photoCount_, nil];
   [self setTitle:title];
}

- (void)scrollToIndex:(NSInteger)index 
{
   CGRect frame = scrollView_.frame;
   frame.origin.x = frame.size.width * index;
   frame.origin.y = 0;
   [scrollView_ scrollRectToVisible:frame animated:NO];
}

- (void)setScrollViewContentSize
{
   NSInteger pageCount = photoCount_;
   if (pageCount == 0) {
      pageCount = 1;
   }

   CGSize size = CGSizeMake(scrollView_.frame.size.width * pageCount, 
                            scrollView_.frame.size.height / 2);   // Cut in half to prevent horizontal scrolling.
   [scrollView_ setContentSize:size];
}

- (void)viewDidLoad 
{
   [super viewDidLoad];
  
   photoCount_ = [dataSource_ numberOfPhotos];
   [self setScrollViewContentSize];
   
   // Setup our photo view cache. We only keep 3 views in
   // memory. NSNull is used as a placeholder for the other
   // elements in the view cache array.
   photoViews_ = [[NSMutableArray alloc] initWithCapacity:photoCount_];
   for (int i=0; i < photoCount_; i++) {
      [photoViews_ addObject:[NSNull null]];
   }
}

- (void)didReceiveMemoryWarning 
{
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewWillAppear:(BOOL)animated 
{
   [super viewWillAppear:animated];
    if ( useFullScreen_ ){
        // The first time the view appears, store away the previous controller's values so we can reset on pop.
        UINavigationBar *navbar = [[self navigationController] navigationBar];
        if (!viewDidAppearOnce_) {
            viewDidAppearOnce_ = YES;
            navbarWasTranslucent_ = [navbar isTranslucent];
            statusBarStyle_ = [[UIApplication sharedApplication] statusBarStyle];
        }
        // Then ensure translucency. Without it, the view will appear below rather than under it.  
        [navbar setTranslucent:YES];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:YES];
    }
    [self layoutScrollViewSubviews];
    [self updateToolbarWithOrientation:[self interfaceOrientation]];
   // Set the scroll view's content size, auto-scroll to the stating photo,
   // and setup the other display elements.
   [self setScrollViewContentSize];
   [self setCurrentIndex:startWithIndex_];
   [self scrollToIndex:startWithIndex_];

   [self setTitleWithCurrentPhotoIndex];
   [self toggleNavButtons];
   [self startChromeDisplayTimer];
   [self cancelCaptionDisplayTimer];
    [[photoViews_ objectAtIndex:currentIndex_] toggleCaption:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated 
{
    if ( useFullScreen_ ){
        // Reset nav bar translucency and status bar style to whatever it was before.
        UINavigationBar *navbar = [[self navigationController] navigationBar];
        [navbar setTranslucent:navbarWasTranslucent_];
        [[UIApplication sharedApplication] setStatusBarStyle:statusBarStyle_ animated:YES];
    }
  [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated 
{
   [self cancelChromeDisplayTimer];
   [super viewDidDisappear:animated];
}

- (void)deleteCurrentPhoto 
{
   if (dataSource_) {
      // TODO: Animate the deletion of the current photo.
      
      NSInteger photoIndexToDelete = currentIndex_;
      [self unloadPhoto:photoIndexToDelete];
      [dataSource_ deleteImageAtIndex:photoIndexToDelete];
      
      photoCount_ -= 1;
      if (photoCount_ == 0) {
         [self showChrome];
         [[self navigationController] popViewControllerAnimated:YES];
      } else {
         NSInteger nextIndex = photoIndexToDelete;
         if (nextIndex == photoCount_) {
            nextIndex -= 1;
         }
         [self setCurrentIndex:nextIndex];
         [self setScrollViewContentSize];
      }
   }
}

- (void)toggleNavButtons 
{
   [previousButton_ setEnabled:(currentIndex_ > 0)];
   [nextButton_ setEnabled:(currentIndex_ < photoCount_ - 1)];
}


#pragma mark -
#pragma mark Frame calculations
#define PADDING  20

- (CGRect)frameForPagingScrollView 
{
   CGRect frame = [[UIScreen mainScreen] bounds];
   frame.origin.x -= PADDING;
   frame.size.width += (2 * PADDING);
   return frame;
}

- (CGRect)frameForPageAtIndex:(NSUInteger)index 
{
   // We have to use our paging scroll view's bounds, not frame, to calculate the page placement. When the device is in
   // landscape orientation, the frame will still be in portrait because the pagingScrollView is the root view controller's
   // view, so its frame is in window coordinate space, which is never rotated. Its bounds, however, will be in landscape
   // because it has a rotation transform applied.
   CGRect bounds = [scrollView_ bounds];
   CGRect pageFrame = bounds;
   pageFrame.size.width -= (2 * PADDING);
   pageFrame.origin.x = (bounds.size.width * index) + PADDING;
   return pageFrame;
}


#pragma mark -
#pragma mark Photo (Page) Management

- (void)loadPhoto:(NSInteger)index
{
   if (index < 0 || index >= photoCount_) {
      return;
   }
   
   id currentPhotoView = [photoViews_ objectAtIndex:index];
   if (NO == [currentPhotoView isKindOfClass:[KTPhotoView class]]) {
      // Load the photo view.
      CGRect frame = [self frameForPageAtIndex:index];
      KTPhotoView *photoView = [[KTPhotoView alloc] initWithFrame:frame];
      [photoView setScroller:self];
      [photoView setIndex:index];
      [photoView setBackgroundColor:[UIColor clearColor]];
      
      // Set the photo image.
      if (dataSource_) {
         if ([dataSource_ respondsToSelector:@selector(imageAtIndex:photoView:)] == NO) {
            UIImage *image = [dataSource_ imageAtIndex:index];
            [photoView setImage:image];
         } else {
            [dataSource_ imageAtIndex:index photoView:photoView];
         }
          if ([dataSource_ respondsToSelector:@selector(captionImageAtIndex:photoView:)] == NO) {
              NSString* caption = [dataSource_ captionAtIndex:index];
              [photoView setCaption:caption];
          } else {
              [dataSource_ captionImageAtIndex:index photoView:photoView];
          }
      }
      
      [scrollView_ addSubview:photoView];
      [photoViews_ replaceObjectAtIndex:index withObject:photoView];
      [photoView release];
   } else {
      // Turn off zooming.
      [currentPhotoView turnOffZoom];
   }
}

- (void)unloadPhoto:(NSInteger)index
{
   if (index < 0 || index >= photoCount_) {
      return;
   }
   
   id currentPhotoView = [photoViews_ objectAtIndex:index];
   if ([currentPhotoView isKindOfClass:[KTPhotoView class]]) {
      [currentPhotoView removeFromSuperview];
      [photoViews_ replaceObjectAtIndex:index withObject:[NSNull null]];
   }
}

- (void)setCurrentIndex:(NSInteger)newIndex
{
   currentIndex_ = newIndex;
   
   [self loadPhoto:currentIndex_];
   [self loadPhoto:currentIndex_ + 1];
   [self loadPhoto:currentIndex_ - 1];
   [self unloadPhoto:currentIndex_ + 2];
   [self unloadPhoto:currentIndex_ - 2];
   
   [self setTitleWithCurrentPhotoIndex];
   [self toggleNavButtons];
    
    [self startCaptionDisplayTimer];
}


#pragma mark -
#pragma mark Rotation Magic

- (void)updateToolbarWithOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
   CGRect toolbarFrame = toolbar_.frame;
   if ((interfaceOrientation) == UIInterfaceOrientationPortrait || (interfaceOrientation) == UIInterfaceOrientationPortraitUpsideDown) {
      toolbarFrame.size.height = ktkDefaultPortraitToolbarHeight;
   } else {
       if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
           toolbarFrame.size.height = ktkDefaultToolbarHeight;
       }
       else {
           toolbarFrame.size.height = ktkDefaultLandscapeToolbarHeight+1;
       }
   }
   
   toolbarFrame.size.width = self.view.frame.size.width;
   toolbarFrame.origin.y =  self.view.frame.size.height - toolbarFrame.size.height;
   toolbar_.frame = toolbarFrame;
}

- (void)layoutScrollViewSubviews
{
   [self setScrollViewContentSize];

   NSArray *subviews = [scrollView_ subviews];
   
   for (KTPhotoView *photoView in subviews) {
      CGPoint restorePoint = [photoView pointToCenterAfterRotation];
      CGFloat restoreScale = [photoView scaleToRestoreAfterRotation];
      [photoView setFrame:[self frameForPageAtIndex:[photoView index]]];
      [photoView setMaxMinZoomScalesForCurrentBounds];
      [photoView restoreCenterPoint:restorePoint scale:restoreScale];
   }
   
   // adjust contentOffset to preserve page location based on values collected prior to location
   CGFloat pageWidth = scrollView_.bounds.size.width;
   CGFloat newOffset = (firstVisiblePageIndexBeforeRotation_ * pageWidth) + (percentScrolledIntoFirstVisiblePage_ * pageWidth);
   scrollView_.contentOffset = CGPointMake(newOffset, 0);
   
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation 
{
   return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation 
                                duration:(NSTimeInterval)duration 
{
   // here, our pagingScrollView bounds have not yet been updated for the new interface orientation. So this is a good
   // place to calculate the content offset that we will need in the new orientation
   CGFloat offset = scrollView_.contentOffset.x;
   CGFloat pageWidth = scrollView_.bounds.size.width;
   
   if (offset >= 0) {
      firstVisiblePageIndexBeforeRotation_ = floorf(offset / pageWidth);
      percentScrolledIntoFirstVisiblePage_ = (offset - (firstVisiblePageIndexBeforeRotation_ * pageWidth)) / pageWidth;
   } else {
      firstVisiblePageIndexBeforeRotation_ = 0;
      percentScrolledIntoFirstVisiblePage_ = offset / pageWidth;
   }    
   
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                         duration:(NSTimeInterval)duration 
{
   [self layoutScrollViewSubviews];
   // Rotate the toolbar.
   [self updateToolbarWithOrientation:toInterfaceOrientation];
    if ( useFullScreen_) {
        // Adjust navigation bar if needed.
        if (isChromeHidden_ && statusbarHidden_ == NO) {
            UINavigationBar *navbar = [[self navigationController] navigationBar];
            CGRect frame = [navbar frame];
            frame.origin.y = 20;
            [navbar setFrame:frame];
        }
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation 
{
   [self startChromeDisplayTimer];
}

- (UIView *)rotatingFooterView 
{
   return toolbar_;
}


#pragma mark -
#pragma mark Chrome Helpers

- (void)toggleChromeDisplay 
{
    BOOL wasHidden = isChromeHidden_;
   [self toggleChrome:!wasHidden];
    [[photoViews_ objectAtIndex:currentIndex_] toggleCaption:wasHidden animated:NO];
}

- (void)toggleChrome:(BOOL)hide 
{
   isChromeHidden_ = hide;
   if (hide) {
      [UIView beginAnimations:nil context:nil];
      [UIView setAnimationDuration:0.4];
   }
    if (useFullScreen_) {
        if ( ! [self isStatusbarHidden] ) {     
            if ([[UIApplication sharedApplication] respondsToSelector:@selector(setStatusBarHidden:withAnimation:)]) {
                [[UIApplication sharedApplication] setStatusBarHidden:hide withAnimation:NO];
            } else {  // Deprecated in iOS 3.2+.
                id sharedApp = [UIApplication sharedApplication];  // Get around deprecation warnings.
                [sharedApp setStatusBarHidden:hide animated:NO];
            }
        }
    }
   CGFloat alpha = hide ? 0.0 : 1.0;
   
    if ( useFullScreen_ ) {
        // Must set the navigation bar's alpha, otherwise the photo
        // view will be pushed until the navigation bar.
        UINavigationBar *navbar = [[self navigationController] navigationBar];
        [navbar setAlpha:alpha];
    }
   [toolbar_ setAlpha:alpha];

   if (hide) {
      [UIView commitAnimations];
   }
   
   if ( ! isChromeHidden_ ) {
      [self startChromeDisplayTimer];
   }
}

- (void)hideChrome 
{
   if (chromeHideTimer_ && [chromeHideTimer_ isValid]) {
      [chromeHideTimer_ invalidate];
      chromeHideTimer_ = nil;
   }
    [self toggleChrome:YES];
     [[photoViews_ objectAtIndex:currentIndex_] toggleCaption:NO animated:YES];
}

- (void)showChrome 
{
   [self toggleChrome:NO];
}


- (void)startChromeDisplayTimer 
{
   [self cancelChromeDisplayTimer];
   chromeHideTimer_ = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                       target:self 
                                                     selector:@selector(hideChrome)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (void)cancelChromeDisplayTimer 
{
   if (chromeHideTimer_) {
      [chromeHideTimer_ invalidate];
      chromeHideTimer_ = nil;
   }
}

-(void)showCaption{
    KTPhotoView* view = [photoViews_ objectAtIndex:currentIndex_];
    [view toggleCaption:YES animated:YES];
}

- (void)startCaptionDisplayTimer 
{
    [self cancelCaptionDisplayTimer];
    captionHideTimer_ = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                        target:self 
                                                      selector:@selector(showCaption)
                                                      userInfo:nil
                                                       repeats:NO] retain];
}

- (void)cancelCaptionDisplayTimer 
{
    if (captionHideTimer_) {
        [captionHideTimer_ invalidate];
        [captionHideTimer_ release];
        captionHideTimer_ = nil;
    }
}

#pragma mark -
#pragma mark UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView 
{
   CGFloat pageWidth = scrollView.frame.size.width;
   float fractionalPage = scrollView.contentOffset.x / pageWidth;
   NSInteger page = floor(fractionalPage);
	if (page != currentIndex_) {
		[self setCurrentIndex:page];
	}
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView 
{
   [self hideChrome];
}


#pragma mark -
#pragma mark Toolbar Actions

- (void)nextPhoto 
{
   [self scrollToIndex:currentIndex_ + 1];
   [self startChromeDisplayTimer];
    [self cancelCaptionDisplayTimer];
    [[photoViews_ objectAtIndex:currentIndex_] toggleCaption:YES animated:NO];
}

- (void)previousPhoto 
{
   [self scrollToIndex:currentIndex_ - 1];
   [self startChromeDisplayTimer];
    [self cancelCaptionDisplayTimer];
    [[photoViews_ objectAtIndex:currentIndex_] toggleCaption:YES animated:NO];
}

- (void)trashPhoto 
{
   UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                            delegate:self
                                                   cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel button text.")
                                              destructiveButtonTitle:NSLocalizedString(@"Delete Photo", @"Delete Photo button text.")
                                                   otherButtonTitles:nil];
   [actionSheet showInView:[self view]];
   [actionSheet release];
}

- (void) exportPhoto
{
   if ([dataSource_ respondsToSelector:@selector(exportImageAtIndex:)])
      [dataSource_ exportImageAtIndex:currentIndex_];
   
   [self startChromeDisplayTimer];
}


#pragma mark -
#pragma mark UIActionSheetDelegate

// Called when a button is clicked. The view will be automatically dismissed after this call returns
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex 
{
   if (buttonIndex == BUTTON_DELETEPHOTO) {
      [self deleteCurrentPhoto];
   }
   [self startChromeDisplayTimer];
}

@end
