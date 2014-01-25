//
//  HBCameraViewController.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/11/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBCameraViewController.h"
#import <GPUImage.h>
#import "HBEditImageViewController.h"
#import "HBFaceView.h"

static NSString *kEditImageSegueIdentifier = @"EditImage";

@interface HBCameraViewController ()
@property (weak, nonatomic) IBOutlet UIView *cameraPreviewView;
@property (weak, nonatomic) IBOutlet UIScrollView *filterScrollView;

@end

@implementation HBCameraViewController {
    //filtered input
    GPUImageStillCamera *_stillCamera;
    GPUImageFilter *_curFilter, *_enteringFilter, *_unprocessedFilter;
    GPUImageView *_curFilteredCameraView, *_enteringFilteredCameraView;
    UIImage *_unprocessedImage;
    
    //face detection
    AVCaptureMetadataOutput *_metadataOutput;
    NSMutableDictionary *_onscreenFaceViews;
    
    //face detection metadata transforms
    CGFloat _xScale, _xOffset, _yScale, _yOffset;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	_onscreenFaceViews = [NSMutableDictionary new];
    [self initCamera];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.navigationController setNavigationBarHidden:YES animated:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    // face detection metadata preparedness
    [self updateMetadataTransform];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

#pragma mark - Status Bar

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
    return UIStatusBarAnimationFade;
}

#pragma mark - Camera Setup

- (void)initCamera
{
    // 1) Final output views
    _curFilteredCameraView = [self createFullSizedGPUImageView];
    _enteringFilteredCameraView = [self createFullSizedGPUImageView];
    [self updateMasksForContentOffset:self.filterScrollView.contentOffset];
    
    // 2) Setup the camera input
    _stillCamera = [[GPUImageStillCamera alloc] init];
    _stillCamera.outputImageOrientation = self.interfaceOrientation;
    [self setupFaceDetection];
    
    // 3) No-filter image pipeline
    _unprocessedFilter = [[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(0, 0, 1.0, 1.0)];
    [_stillCamera addTarget:_unprocessedFilter];
    [_stillCamera startCameraCapture];
    
    // 4) initial filters
    _curFilter = [[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(0, 0, 1.0, 1.0)];
    [self setCameraFilter:_curFilter forView:_curFilteredCameraView replacingFilter:nil];
    _enteringFilter = [[GPUImageToonFilter alloc] init];
    [self setCameraFilter:_enteringFilter forView:_enteringFilteredCameraView replacingFilter:nil];
    
    //   filter changing scroll view
    self.filterScrollView.contentSize = CGSizeMake(self.view.bounds.size.width*2, self.view.bounds.size.height);
    [self.filterScrollView setContentOffset:CGPointMake(0, 0)];
    self.filterScrollView.delegate = self;
}

- (GPUImageView *)createFullSizedGPUImageView
{
    GPUImageView *v = [[GPUImageView alloc] initWithFrame:self.cameraPreviewView.bounds];
    v.fillMode = kGPUImageFillModePreserveAspectRatioAndFill;
    
    [self.cameraPreviewView addSubview:v];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cameraPreviewView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[view]|" options:0 metrics:nil views:@{@"view":v}]];
    [self.cameraPreviewView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[view]|" options:0 metrics:nil views:@{@"view":v}]];
    
    CALayer *mask = ({
        CALayer *m = [CALayer layer];
        m.backgroundColor = [UIColor blackColor].CGColor;
        m.frame = self.cameraPreviewView.frame;
        m;
    });
    v.layer.mask = mask;
    
    return v;
}

- (void)setCameraFilter:(GPUImageFilter *)newFilter forView:(GPUImageView *)view replacingFilter:(GPUImageFilter *)filterToBeReplaced
{
    if (filterToBeReplaced) {
        [_stillCamera pauseCameraCapture];
        [filterToBeReplaced removeAllTargets];
        [_stillCamera removeTarget:filterToBeReplaced];
    }
    
    // OPTIMIZE: we can -forceProcessingAtSize: or -forceProcessingAtSizeRespectingAspectRatio for the filter view
    // see https://github.com/BradLarson/GPUImage/issues/751
    // but it's not a simple drop in... the resulting processed image has to play with our aspect
    // ratio calculations throughout the app
    [_stillCamera addTarget:newFilter];
    [newFilter addTarget:view];

    [_stillCamera resumeCameraCapture];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration {
    //TODO: update scroll view and masks
    _stillCamera.outputImageOrientation = toInterfaceOrientation;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    //TODO: update scroll view and masks
    [self updateMetadataTransform];
}

#pragma mark Face Detection Shit
//see WWDC 2013 session 610

- (void)setupFaceDetection
{
    AVCaptureSession *session = [_stillCamera captureSession];
    
    _metadataOutput = [AVCaptureMetadataOutput new];
    if (![session canAddOutput:_metadataOutput]) {
        //TODO: BUG OUT!
        _metadataOutput = nil;
        return;
    }
    
    // Metadata processing will be fast, and mostly updating UI which should be done on the main thread
	// So just use the main dispatch queue instead of creating a separate one
	[_metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
	[session addOutput:_metadataOutput];
	
	if ( ![_metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeFace] ) {
		// face detection isn't supported via AV Foundation
        //TODO: BUG OUT!
		[self teardownAVFoundationFaceDetection];
		return;
	}
    
	_metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
	[self updateAVFoundationFaceDetection];
}

- (void)updateAVFoundationFaceDetection
{
	if (_metadataOutput){
		[[_metadataOutput connectionWithMediaType:AVMediaTypeMetadata] setEnabled:YES];
    }
}

- (void)teardownAVFoundationFaceDetection
{
	if (_metadataOutput){
		[[_stillCamera captureSession] removeOutput:_metadataOutput];
    }
	_metadataOutput = nil;
    for (UIView *fv in _onscreenFaceViews) {
        [fv removeFromSuperview];
    }
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)faces fromConnection:(AVCaptureConnection *)connection
{
    //faces are assigned unique (never reused) IDs while in view
    NSMutableSet* unseen = [NSMutableSet setWithArray:_onscreenFaceViews.allKeys];
	NSMutableSet* seen = [NSMutableSet setWithCapacity:faces.count];
    
    // Explicitly begin display updates, disabling implicity actions
    // This is from the WWDC sample code, improves performance by eliminating animations
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    // 1) move, or add new, faces
    for (AVMetadataFaceObject *face in faces) {
        NSNumber *faceID = @(face.faceID);
        [unseen removeObject:faceID];
        [seen addObject:faceID];
        
        HBFaceView *faceView = _onscreenFaceViews[faceID];
        if (!faceView) {
            faceView = ({
                HBFaceView *v = [[NSBundle mainBundle] loadNibNamed:@"HBFaceView" owner:nil options:nil][0];
                v.layer.cornerRadius = 3.0f;
                v.layer.borderWidth = 2.0f;
                v.layer.borderColor = [UIColor redColor].CGColor;
                v;
            });
            _onscreenFaceViews[faceID] = faceView;
            [self.cameraPreviewView addSubview:faceView];
        }
     
        //The AVMetadataFaceObject is relative to the raw camera input.
        //We're not using a standard AVCaptureVideoPreviewLayer, need to replicate the functionality of
        // -transformedMetadataObjectForMetadataObject: to transform the raw metadata and make it relative
        // to our preview view...
        CGRect adjustedFaceFrame;
        CGFloat adjustedYaw, adjustedRoll;
        [self forFace:face transformedBounds:&adjustedFaceFrame yaw:&adjustedYaw roll:&adjustedRoll];
        
        //TODO: take yaw into account as well?
        faceView.bounds = CGRectMake(0, 0, adjustedFaceFrame.size.width, adjustedFaceFrame.size.height);
        faceView.center = CGPointMake(adjustedFaceFrame.origin.x + adjustedFaceFrame.size.width/2.f,
                                      adjustedFaceFrame.origin.y + adjustedFaceFrame.size.height/2.f);
        if (face.hasRollAngle) {
            faceView.transform = CGAffineTransformMakeRotation(adjustedRoll*(M_PI/180.f));
        }
    }
    
    // 2) remove faces not detected
    for (NSNumber *unseenFaceID in unseen) {
        UIView *faceView = _onscreenFaceViews[unseenFaceID];
        [faceView removeFromSuperview];
        [_onscreenFaceViews removeObjectForKey:unseenFaceID];
    }
    
    [CATransaction commit];
}

#pragma mark Target-Action

- (IBAction)captureImageTapped:(UIButton *)sender {

    //TODO: next line for faster image capture; must reset to capture again
//    [_unprocessedFilter prepareForImageCapture];
    [_stillCamera capturePhotoAsImageProcessedUpToFilter:_unprocessedFilter withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        if (!error) {
            _unprocessedImage = processedImage;
            [self performSegueWithIdentifier:kEditImageSegueIdentifier sender:self];
        } else {
            //TODO
        }
    }];
}

#pragma mark Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:kEditImageSegueIdentifier]) {
        HBEditImageViewController *editVC = (HBEditImageViewController *)segue.destinationViewController;
        editVC.unprocessedImage = _unprocessedImage;
    } else {
        //not expecting this
    }
}

#pragma mark - Metadata Transform Maths

//NB: yaw not currently transformed
- (void)forFace:(AVMetadataFaceObject *)face transformedBounds:(CGRect *)bounds yaw:(CGFloat *)yaw roll:(CGFloat *)roll
{
    CGRect faceBounds = face.bounds;
    CGFloat deviceRoll;
    
    //NB: this is only built for back camera right now
    switch (self.interfaceOrientation) {
        case UIInterfaceOrientationPortrait:
        {
            //rear cam is rotated 90deg CCW
            deviceRoll = 270;
            faceBounds = CGRectMake((1.0-faceBounds.origin.y) - faceBounds.size.height,
                                    faceBounds.origin.x,
                                    faceBounds.size.height,
                                    faceBounds.size.width);
        }; break;
        case UIInterfaceOrientationPortraitUpsideDown:
        {
            //rear cam is rotated 90deg CW
            deviceRoll = 90;
            faceBounds = CGRectMake(faceBounds.origin.y,
                                    (1.0-faceBounds.origin.x) - faceBounds.size.width,
                                    faceBounds.size.height,
                                    faceBounds.size.width);
        }; break;
        case UIInterfaceOrientationLandscapeLeft:
        {
            //rear cam is upside down
            deviceRoll = 180;
            faceBounds = CGRectMake((1.0-faceBounds.origin.x) - faceBounds.size.width,
                                    (1.0-faceBounds.origin.y) - faceBounds.size.height,
                                    faceBounds.size.width,
                                    faceBounds.size.height);
        }; break;
        case UIInterfaceOrientationLandscapeRight:
        {
            //natural orientation of rear camera
            deviceRoll = 0;
        }; break;
    }
    
    //OPTIMIZE: wrap this and calculations above into one precomputed matrix multiplication
    *bounds = CGRectMake((faceBounds.origin.x * _xScale) + _xOffset,
                         (faceBounds.origin.y * _yScale) + _yOffset,
                         faceBounds.size.width * _xScale,
                         faceBounds.size.height * _yScale);
    
    //roll is side-to-side tilt of face
    if (face.hasRollAngle){
        CGFloat adjustedRoll = face.rollAngle - deviceRoll;
        if (adjustedRoll > 180.f) {
            adjustedRoll = adjustedRoll - 360.f;
        }
        *roll = adjustedRoll;
    }
    
    //yaw is rotation about vertical axis
//    if (face.hasYawAngle) {
//        DLog(@"YAW:  %f", face.yawAngle);
//    } else {
//        DLog(@"NO-YAW");
//    }
}

//this must be called when view changes size, device rotates, or camera changes
- (void)updateMetadataTransform
{
    CGSize currentViewSize = _curFilteredCameraView.bounds.size;
    CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(_curFilteredCameraView.inputImageSize, _curFilteredCameraView.bounds);
    
    switch(_curFilteredCameraView.fillMode)
    {
        case kGPUImageFillModeStretch:
        {
            _xScale = currentViewSize.width;
            _xOffset = 0;
            _yScale = currentViewSize.height;
            _yOffset = 0;
        }; break;
        case kGPUImageFillModePreserveAspectRatio:
        {
            _xScale = insetRect.size.width;
            _xOffset = insetRect.origin.x;
            _yScale = insetRect.size.height;
            _yOffset = insetRect.origin.y;
        }; break;
        case kGPUImageFillModePreserveAspectRatioAndFill:
        {
            CGFloat widthScaling = currentViewSize.height / insetRect.size.height;
            CGFloat heightScaling = currentViewSize.width / insetRect.size.width;
            
            _xScale = currentViewSize.width * widthScaling;
            _xOffset = -(_xScale-currentViewSize.width)/2.f;
            _yScale = currentViewSize.height * heightScaling;
            _yOffset = -(_yScale-currentViewSize.height)/2.f;
        }; break;
    }
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateMasksForContentOffset:scrollView.contentOffset];
}

- (void)updateMasksForContentOffset:(CGPoint)contentOffset
{
    [CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    //masks are all black; black means "show what's behind me"
    //current mask is fully covering view, entering mask is moving in
    _curFilteredCameraView.layer.mask.frame = CGRectMake(-contentOffset.x, 0, self.cameraPreviewView.bounds.size.width, self.cameraPreviewView.bounds.size.height);
    _enteringFilteredCameraView.layer.mask.frame = CGRectMake(self.cameraPreviewView.bounds.size.width - contentOffset.x, 0, self.cameraPreviewView.bounds.size.width, self.cameraPreviewView.bounds.size.height);
    
    [CATransaction commit];
}

@end
